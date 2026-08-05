package main

import (
	"context"
	"crypto/rand"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"rateboard/backend-service/internal/api"
	"rateboard/backend-service/internal/config"
	queue "rateboard/backend-service/internal/messaging"
	"rateboard/backend-service/internal/repository"
)

func main() {
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo})))
	cfg := config.Load()
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	store, err := repository.New(ctx, cfg.DatabaseURL)
	if err != nil {
		slog.Error("database connection failed", "service", "history-service", "event", "database_connection_failed", "error_type", fmt.Sprintf("%T", err))
		os.Exit(1)
	}
	defer store.Close()

	var consumer *queue.Consumer
	if cfg.RabbitMQEnabled {
		consumer = &queue.Consumer{
			URL: cfg.RabbitMQURL, Exchange: cfg.RabbitMQEventsExchange,
			Queue: cfg.RabbitMQObservationsQueue, RoutingKey: cfg.RabbitMQObservationRoute,
			Store: store,
		}
		go consumer.Run(ctx)
	}
	mqReady := func() bool { return !cfg.RabbitMQEnabled || (consumer != nil && consumer.Ready()) }
	server := &http.Server{
		Addr:              cfg.Address,
		Handler:           (&api.Server{Store: store, MQReady: mqReady}).Handler(),
		ReadHeaderTimeout: 5 * time.Second,
	}
	go func() {
		slog.Info("history service listening", "service", "history-service", "event", "listening", "address", cfg.Address)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("HTTP server failed", "service", "history-service", "event", "http_server_failed", "error", err)
			os.Exit(1)
		}
	}()

	if cfg.RabbitMQEnabled && cfg.StartupBackfillEnabled {
		publisher := &queue.CommandPublisher{
			URL: cfg.RabbitMQURL, Exchange: cfg.RabbitMQCommandsExchange,
			Queue: cfg.RabbitMQCommandsQueue, RoutingKey: cfg.RabbitMQCommandRoute,
		}
		go planBackfill(ctx, store, publisher, cfg.StartupBackfillMaxDays)
	}

	<-ctx.Done()
	shutdown, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = server.Shutdown(shutdown)
}

func planBackfill(ctx context.Context, store *repository.Store, publisher *queue.CommandPublisher, maximumDays int) {
	select {
	case <-ctx.Done():
		return
	case <-time.After(5 * time.Second):
	}
	if maximumDays > 365 {
		maximumDays = 365
	}
	latest, err := store.LatestTimestamps(ctx)
	if err != nil {
		slog.Error("backfill plan failed", "service", "history-service", "event", "backfill_plan_failed", "error_type", fmt.Sprintf("%T", err))
		return
	}
	now := time.Now().UTC()
	for _, instrumentID := range api.CatalogIDs() {
		from := now.AddDate(0, 0, -maximumDays)
		if timestamp, exists := latest[instrumentID]; exists && timestamp.After(from) {
			from = timestamp
		}
		requestID := newUUID()
		commandID := fmt.Sprintf("%s:%s:%s", instrumentID, from.Format("2006-01-02"), now.Format("2006-01-02"))
		command := queue.BackfillCommand{
			CommandID: commandID, CommandType: "rates.backfill.requested", Schema: 1,
			RequestID: requestID, Instrument: instrumentID,
			From: from.Format(time.RFC3339), To: now.Format(time.RFC3339),
		}
		publishCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
		err := publisher.PublishBackfill(publishCtx, command)
		cancel()
		if err != nil {
			for attempt := 2; attempt <= 10 && err != nil; attempt++ {
				select {
				case <-ctx.Done():
					return
				case <-time.After(2 * time.Second):
				}
				publishCtx, cancel = context.WithTimeout(ctx, 10*time.Second)
				err = publisher.PublishBackfill(publishCtx, command)
				cancel()
			}
			if err != nil {
				slog.Error("backfill command failed", "service", "history-service", "event", "backfill_command_failed", "instrument_id", instrumentID, "error_type", fmt.Sprintf("%T", err))
				return
			}
		}
	}
	slog.Info("backfill plan queued", "service", "history-service", "event", "backfill_plan_queued", "instruments", len(api.CatalogIDs()))
}

func newUUID() string {
	var value [16]byte
	if _, err := rand.Read(value[:]); err != nil {
		panic(err)
	}
	value[6] = (value[6] & 0x0f) | 0x40
	value[8] = (value[8] & 0x3f) | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", value[0:4], value[4:6], value[6:8], value[8:10], value[10:16])
}
