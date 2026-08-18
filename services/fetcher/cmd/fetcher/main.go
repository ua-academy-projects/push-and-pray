package main

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"sync/atomic"
	"syscall"
	"time"

	"oil-price-tracker/fetcher/internal/broker"
	"oil-price-tracker/fetcher/internal/config"
	"oil-price-tracker/fetcher/internal/provider"
	"oil-price-tracker/fetcher/internal/schedule"
	"oil-price-tracker/fetcher/internal/service"
)

func main() {
	configuration, err := config.Load()
	if err != nil {
		slog.Error("invalid configuration", "error", err)
		os.Exit(1)
	}
	httpClient := &http.Client{Timeout: configuration.RequestTimeout}
	var priceProvider provider.Provider = provider.Mock{}
	if configuration.DataProvider == "oilpriceapi" {
		priceProvider = provider.OilPriceAPI{APIKey: configuration.OilPriceAPIKey, Client: httpClient}
	}
	collector := service.New(priceProvider, broker.Publisher{
		URL:        configuration.RabbitMQURL,
		Exchange:   configuration.RabbitExchange,
		Queue:      configuration.RabbitQueue,
		RoutingKey: configuration.RabbitRoute,
	})

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	var nextRunUnix atomic.Int64
	run := func(slot time.Time) {
		jobContext, cancel := context.WithTimeout(ctx, configuration.RequestTimeout*20)
		defer cancel()
		if _, err := collector.Run(jobContext, slot); err != nil {
			slog.Error("scheduled collection ended with an error", "error", err)
		}
	}
	go func() {
		if configuration.FetchOnStartup {
			run(schedule.LatestSlot(time.Now(), configuration.CronHours, configuration.Timezone))
		}
		for {
			nextRun := schedule.NextSlot(time.Now(), configuration.CronHours, configuration.Timezone)
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
	mux.HandleFunc("GET /health", func(response http.ResponseWriter, _ *http.Request) {
		running, last, lastError := collector.Status()
		var nextRun any
		if unix := nextRunUnix.Load(); unix > 0 {
			nextRun = time.Unix(unix, 0).UTC()
		}
		writeJSON(response, http.StatusOK, map[string]any{
			"status": "ok", "provider": configuration.DataProvider, "running": running,
			"delivery":    "rabbitmq",
			"schedule":    map[string]any{"hours": configuration.CronHours, "timezone": configuration.Timezone.String(), "next_run": nextRun},
			"last_result": last, "last_error": lastError,
		})
	})
	mux.HandleFunc("POST /v1/fetch", func(response http.ResponseWriter, request *http.Request) {
		running, _, _ := collector.Status()
		if running {
			writeJSON(response, http.StatusConflict, map[string]string{"detail": "collection is already running"})
			return
		}
		result, err := collector.Run(request.Context(), schedule.LatestSlot(time.Now(), configuration.CronHours, configuration.Timezone))
		if err != nil {
			writeJSON(response, http.StatusBadGateway, map[string]string{"detail": err.Error()})
			return
		}
		writeJSON(response, http.StatusOK, result)
	})

	server := &http.Server{
		Addr: configuration.ListenAddress, Handler: mux,
		ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 10 * time.Second, WriteTimeout: 30 * time.Second,
	}
	go func() {
		slog.Info("API Fetcher started", "address", configuration.ListenAddress, "provider", configuration.DataProvider)
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			slog.Error("HTTP server failed", "error", err)
			stop()
		}
	}()

	<-ctx.Done()
	shutdownContext, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := server.Shutdown(shutdownContext); err != nil {
		slog.Error("HTTP shutdown failed", "error", err)
	}
}

func writeJSON(response http.ResponseWriter, status int, payload any) {
	response.Header().Set("Content-Type", "application/json")
	response.WriteHeader(status)
	if err := json.NewEncoder(response).Encode(payload); err != nil {
		slog.Error("write response", "error", err)
	}
}
