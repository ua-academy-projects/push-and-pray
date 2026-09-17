package main

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"regexp"
	"strings"
	"sync/atomic"
	"syscall"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"

	"oil-price-tracker/fetcher/internal/config"
	"oil-price-tracker/fetcher/internal/pgmq"
	"oil-price-tracker/fetcher/internal/provider"
	"oil-price-tracker/fetcher/internal/rabbitmq"
	"oil-price-tracker/fetcher/internal/schedule"
	"oil-price-tracker/fetcher/internal/service"
)

func main() {
	closeLog, err := configureLogging()
	if err != nil {
		panic(err)
	}
	defer closeLog()

	configuration, err := config.Load()
	if err != nil {
		slog.Error("invalid configuration", "error", err)
		os.Exit(1)
	}

	httpClient := &http.Client{
		Timeout: configuration.RequestTimeout,
	}

	var priceProvider provider.Provider = provider.Mock{}

	if configuration.DataProvider == "oilpriceapi" {
		priceProvider = provider.OilPriceAPI{
			APIKey: configuration.OilPriceAPIKey,
			Client: httpClient,
		}
	}

	var publisher service.Publisher
	var database *sql.DB

	if configuration.QueueBackend == "rabbitmq" {
		publisher = rabbitmq.Publisher{
			URL:        configuration.RabbitMQURL,
			Exchange:   configuration.RabbitExchange,
			Queue:      configuration.QueueName,
			RoutingKey: configuration.RabbitRoute,
		}
	} else {
		database, err = sql.Open("pgx", configuration.DatabaseURL)
		if err != nil {
			slog.Error("open PostgreSQL connection", "error", err)
			os.Exit(1)
		}
		defer database.Close()

		if err := database.Ping(); err != nil {
			slog.Error("connect to PostgreSQL", "error", err)
			os.Exit(1)
		}

		publisher = pgmq.Publisher{
			DB:        database,
			QueueName: configuration.QueueName,
		}
	}

	collector := service.New(priceProvider, publisher)

	ctx, stop := signal.NotifyContext(
		context.Background(),
		syscall.SIGINT,
		syscall.SIGTERM,
	)
	defer stop()

	var nextRunUnix atomic.Int64

	run := func(slot time.Time) {
		jobContext, cancel := context.WithTimeout(
			ctx,
			configuration.RequestTimeout*20,
		)
		defer cancel()

		if _, err := collector.Run(jobContext, slot); err != nil {
			slog.Error(
				"scheduled collection ended with an error",
				"error",
				err,
			)
		}
	}

	go func() {
		if configuration.FetchOnStartup {
			run(
				schedule.LatestSlot(
					time.Now(),
					configuration.CronHours,
					configuration.Timezone,
				),
			)
		}

		for {
			nextRun := schedule.NextSlot(
				time.Now(),
				configuration.CronHours,
				configuration.Timezone,
			)

			nextRunUnix.Store(nextRun.Unix())

			timer := time.NewTimer(time.Until(nextRun))

			select {
			case <-ctx.Done():
				timer.Stop()
				return

			case <-timer.C:
				run(nextRun)
			}
		}
	}()

	mux := http.NewServeMux()

	mux.HandleFunc("GET /health", func(
		response http.ResponseWriter,
		_ *http.Request,
	) {
		running, last, lastError := collector.Status()

		var nextRun any

		if unix := nextRunUnix.Load(); unix > 0 {
			nextRun = time.Unix(unix, 0).UTC()
		}

		writeJSON(
			response,
			http.StatusOK,
			map[string]any{
				"status":   "ok",
				"provider": configuration.DataProvider,
				"running":  running,
				"delivery": configuration.QueueBackend,
				"queue":    configuration.QueueName,
				"schedule": map[string]any{
					"hours":    configuration.CronHours,
					"timezone": configuration.Timezone.String(),
					"next_run": nextRun,
				},
				"last_result": last,
				"last_error":  lastError,
			},
		)
	})

	mux.HandleFunc("POST /v1/fetch", func(
		response http.ResponseWriter,
		request *http.Request,
	) {
		running, _, _ := collector.Status()

		if running {
			writeJSON(
				response,
				http.StatusConflict,
				map[string]string{
					"detail": "collection is already running",
				},
			)
			return
		}

		result, err := collector.Run(
			request.Context(),
			schedule.LatestSlot(
				time.Now(),
				configuration.CronHours,
				configuration.Timezone,
			),
		)

		if err != nil {
			writeJSON(
				response,
				http.StatusBadGateway,
				map[string]string{
					"detail": err.Error(),
				},
			)
			return
		}

		writeJSON(response, http.StatusOK, result)
	})

	server := &http.Server{
		Addr:              configuration.ListenAddress,
		Handler:           accessLogMiddleware(mux),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      30 * time.Second,
	}

	go func() {
		slog.Info(
			"API Fetcher started",
			"address",
			configuration.ListenAddress,
			"provider",
			configuration.DataProvider,
			"queue",
			configuration.QueueName,
		)

		if err := server.ListenAndServe(); err != nil &&
			!errors.Is(err, http.ErrServerClosed) {
			slog.Error("HTTP server failed", "error", err)
			stop()
		}
	}()

	<-ctx.Done()

	shutdownContext, cancel := context.WithTimeout(
		context.Background(),
		5*time.Second,
	)
	defer cancel()

	if err := server.Shutdown(shutdownContext); err != nil {
		slog.Error("HTTP shutdown failed", "error", err)
	}
}

var validRequestID = regexp.MustCompile(`^[A-Za-z0-9._:-]{1,128}$`)

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (recorder *statusRecorder) WriteHeader(status int) {
	recorder.status = status
	recorder.ResponseWriter.WriteHeader(status)
}

func accessLogMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		requestID := request.Header.Get("X-Request-ID")
		if !validRequestID.MatchString(requestID) {
			random := make([]byte, 16)
			if _, err := rand.Read(random); err != nil {
				requestID = "unavailable"
			} else {
				requestID = hex.EncodeToString(random)
			}
		}
		response.Header().Set("X-Request-ID", requestID)
		recorder := &statusRecorder{ResponseWriter: response, status: http.StatusOK}
		started := time.Now()
		next.ServeHTTP(recorder, request)
		route := request.Pattern
		if route == "" {
			route = "<unmatched>"
		}
		slog.Info(
			"HTTP request completed",
			"event", "http_access",
			"method", request.Method,
			"route", route,
			"status", recorder.status,
			"duration_ms", float64(time.Since(started).Microseconds())/1000,
			"request_id", requestID,
		)
	})
}

func configureLogging() (func(), error) {
	writers := []io.Writer{os.Stdout}
	var file *os.File
	if path := os.Getenv("OILSCOPE_LOG_FILE"); path != "" {
		var err error
		file, err = os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o600)
		if err != nil {
			return nil, err
		}
		writers = append(writers, file)
	}
	handler := slog.NewJSONHandler(io.MultiWriter(writers...), &slog.HandlerOptions{
		ReplaceAttr: func(_ []string, attribute slog.Attr) slog.Attr {
			switch attribute.Key {
			case slog.TimeKey:
				attribute.Key = "timestamp"
			case slog.MessageKey:
				attribute.Key = "message"
			case slog.LevelKey:
				attribute.Value = slog.StringValue(strings.ToLower(attribute.Value.String()))
			}
			return attribute
		},
	})
	slog.SetDefault(slog.New(handler).With("service", "fetcher"))
	return func() {
		if file != nil {
			_ = file.Close()
		}
	}, nil
}

func writeJSON(
	response http.ResponseWriter,
	status int,
	payload any,
) {
	response.Header().Set("Content-Type", "application/json")
	response.WriteHeader(status)

	if err := json.NewEncoder(response).Encode(payload); err != nil {
		slog.Error("write response", "error", err)
	}
}
