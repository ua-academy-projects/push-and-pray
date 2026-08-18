package pgmq

import (
	"context"
	"database/sql"
	"os"
	"testing"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"

	"oil-price-tracker/fetcher/internal/model"
)

func TestPublisherDeduplicatesEventKey(t *testing.T) {
	databaseURL := os.Getenv("PGMQ_TEST_DATABASE_URL")
	if databaseURL == "" {
		t.Skip("PGMQ_TEST_DATABASE_URL is not configured")
	}

	database, err := sql.Open("pgx", databaseURL)
	if err != nil {
		t.Fatalf("open database: %v", err)
	}
	defer database.Close()

	ctx := context.Background()

	if err := database.PingContext(ctx); err != nil {
		t.Fatalf("ping database: %v", err)
	}

	if _, err := database.ExecContext(
		ctx,
		"DELETE FROM published_queue_events",
	); err != nil {
		t.Fatalf("clear event ledger: %v", err)
	}

	var purged int64

	if err := database.QueryRowContext(
		ctx,
		"SELECT pgmq.purge_queue($1)",
		"price_observations",
	).Scan(&purged); err != nil {
		t.Fatalf("purge queue: %v", err)
	}

	scheduledFor := time.Date(
		2026,
		8,
		18,
		12,
		0,
		0,
		0,
		time.UTC,
	)

	observations := []model.Observation{
		{
			InstrumentCode: "WTI_USD_BBL",
			InstrumentName: "WTI Crude Oil",
			Category:       "crude_oil",
			Price:          "68.42",
			Currency:       "USD",
			Unit:           "USD per barrel",
			Source:         "OilPriceAPI",
			SourceSeriesID: "WTI_USD",
			SourcePeriod:   "2026-08-18",
			SourceObservedAt: scheduledFor.Add(
				-time.Minute,
			),
			ScheduledFor: scheduledFor,
			FetchedAt: scheduledFor.Add(
				2 * time.Second,
			),
			SourceURL: "https://api.oilpriceapi.com/v1/prices/latest",
			RawData: map[string]any{
				"code":  "WTI_USD",
				"price": "68.42",
			},
		},
	}

	publisher := Publisher{
		DB:        database,
		QueueName: "price_observations",
	}

	if err := publisher.Publish(ctx, observations); err != nil {
		t.Fatalf("first publish: %v", err)
	}

	if err := publisher.Publish(ctx, observations); err != nil {
		t.Fatalf("duplicate publish: %v", err)
	}

	var queuedMessages int

	if err := database.QueryRowContext(
		ctx,
		"SELECT COUNT(*) FROM pgmq.q_price_observations",
	).Scan(&queuedMessages); err != nil {
		t.Fatalf("count queue messages: %v", err)
	}

	if queuedMessages != 1 {
		t.Fatalf(
			"expected 1 queued message, got %d",
			queuedMessages,
		)
	}

	var eventKeys int

	if err := database.QueryRowContext(
		ctx,
		"SELECT COUNT(*) FROM published_queue_events",
	).Scan(&eventKeys); err != nil {
		t.Fatalf("count event keys: %v", err)
	}

	if eventKeys != 1 {
		t.Fatalf(
			"expected 1 event key, got %d",
			eventKeys,
		)
	}
}
