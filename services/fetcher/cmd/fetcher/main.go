package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"sync/atomic"
	"syscall"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"

	"oil-price-tracker/fetcher/internal/config"
	"oil-price-tracker/fetcher/internal/provider"
	"oil-price-tracker/fetcher/internal/rabbitmq"
	"oil-price-tracker/fetcher/internal/schedule"
	"oil-price-tracker/fetcher/internal/service"
)

func main() {
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

	database, err := sql.Open("pgx", configuration.DatabaseURL)
	if err != nil {
		slog.Error("open PostgreSQL connection", "error", err)
		os.Exit(1)
	}
	defer database.Close()

	if err := database.Ping(); err != nil {
		slog.Error("connect to PostgreSQL", "error", err)
		os.Exit(1)
	}

	publisher := &rabbitmq.Publisher{DB: database, URL: configuration.RabbitURL, CAFile: configuration.RabbitCA,
		Exchange: configuration.RabbitExchange, RoutingKey: configuration.RabbitRoutingKey, QueueName: configuration.QueueName,
		Timeout: configuration.RabbitTimeout, PollInterval: configuration.OutboxPollInterval, BatchSize: configuration.OutboxBatchSize}
	collector := service.New(priceProvider, publisher)

	ctx, stop := signal.NotifyContext(
		context.Background(),
		syscall.SIGINT,
		syscall.SIGTERM,
	)
	defer stop()
	dispatcherDone := make(chan struct{})
	go func() { defer close(dispatcherDone); publisher.Run(ctx) }()
	defer func() { stop(); <-dispatcherDone }()

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
		request *http.Request,
	) {
		outboxContext, cancelOutbox := context.WithTimeout(request.Context(), configuration.RabbitTimeout)
		outbox := outboxBacklog(outboxContext, database)
		cancelOutbox()

		running, last, lastError := collector.Status()

		var nextRun any

		if unix := nextRunUnix.Load(); unix > 0 {
			nextRun = time.Unix(unix, 0).UTC()
		}

		statusCode := http.StatusOK
		status := "ok"

		if !publisher.Ready.Load() {
			statusCode = http.StatusServiceUnavailable
			status = "not_ready"
		}

		writeJSON(
			response,
			statusCode,
			map[string]any{
				"status":   status,
				"provider": configuration.DataProvider,
				"running":  running,
				"delivery": "rabbitmq",
				"queue":    configuration.QueueName,
				"schedule": map[string]any{
					"hours":    configuration.CronHours,
					"timezone": configuration.Timezone.String(),
					"next_run": nextRun,
				},
				"last_result": last,
				"last_error":  lastError,
				"outbox":      outbox,
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
		Handler:           mux,
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

// outboxBacklog reports the durable outbox's pending backlog for operator
// visibility (queue depth is not otherwise observable without querying
// Postgres directly). It never fails the health check itself: a query error
// is surfaced as a diagnostic field, not a 503, since it reflects a stats
// query, not the publisher's own readiness.
func outboxBacklog(ctx context.Context, database *sql.DB) map[string]any {
	var pendingCount int

	var oldestPendingAt sql.NullTime

	err := database.QueryRowContext(
		ctx,
		`SELECT COUNT(*), MIN(created_at) FROM published_queue_events WHERE status = 'pending'`,
	).Scan(&pendingCount, &oldestPendingAt)
	if err != nil {
		slog.Error("query outbox backlog", "error", err)

		return map[string]any{"error": "unavailable"}
	}

	var oldestPendingSeconds any

	if oldestPendingAt.Valid {
		oldestPendingSeconds = time.Since(oldestPendingAt.Time).Seconds()
	}

	return map[string]any{
		"pending_count":          pendingCount,
		"oldest_pending_seconds": oldestPendingSeconds,
	}
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
