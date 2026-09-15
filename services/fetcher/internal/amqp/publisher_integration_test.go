package amqp

import (
	"context"
	"database/sql"
	"os"
	"testing"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
	amqp "github.com/rabbitmq/amqp091-go"

	"oil-price-tracker/fetcher/internal/model"
)

const (
	testExchange   = "oil.price.events.test"
	testQueue      = "fetcher.publisher.test"
	testRoutingKey = "prices.observed"
)

func testObservations() []model.Observation {
	scheduledFor := time.Date(2026, 8, 18, 12, 0, 0, 0, time.UTC)

	return []model.Observation{
		{
			InstrumentCode:   "WTI_USD_BBL",
			InstrumentName:   "WTI Crude Oil",
			Category:         "crude_oil",
			Price:            "68.42",
			Currency:         "USD",
			Unit:             "USD per barrel",
			Source:           "OilPriceAPI",
			SourceSeriesID:   "WTI_USD",
			SourcePeriod:     "2026-08-18",
			SourceObservedAt: scheduledFor.Add(-time.Minute),
			ScheduledFor:     scheduledFor,
			FetchedAt:        scheduledFor.Add(2 * time.Second),
			SourceURL:        "https://api.oilpriceapi.com/v1/prices/latest",
			RawData: map[string]any{
				"code":  "WTI_USD",
				"price": "68.42",
			},
		},
	}
}

// setup opens the ledger database and the broker, and leaves the test queue
// bound and empty. It skips when either backend is not configured.
func setup(t *testing.T) (*sql.DB, string) {
	t.Helper()

	databaseURL := os.Getenv("PGMQ_TEST_DATABASE_URL")
	brokerURL := os.Getenv("AMQP_TEST_URL")

	if databaseURL == "" || brokerURL == "" {
		t.Skip("PGMQ_TEST_DATABASE_URL and AMQP_TEST_URL are not configured")
	}

	database, err := sql.Open("pgx", databaseURL)
	if err != nil {
		t.Fatalf("open database: %v", err)
	}
	t.Cleanup(func() { database.Close() })

	ctx := context.Background()

	if _, err := database.ExecContext(ctx, "DELETE FROM published_queue_events"); err != nil {
		t.Fatalf("clear event ledger: %v", err)
	}

	connection, err := amqp.Dial(brokerURL)
	if err != nil {
		t.Fatalf("connect to the broker: %v", err)
	}
	t.Cleanup(func() { connection.Close() })

	channel, err := connection.Channel()
	if err != nil {
		t.Fatalf("open a channel: %v", err)
	}
	t.Cleanup(func() { channel.Close() })

	if err := channel.ExchangeDeclare(testExchange, "topic", true, false, false, false, nil); err != nil {
		t.Fatalf("declare exchange: %v", err)
	}

	if _, err := channel.QueueDeclare(testQueue, true, false, false, false, nil); err != nil {
		t.Fatalf("declare queue: %v", err)
	}

	if err := channel.QueueBind(testQueue, testRoutingKey, testExchange, false, nil); err != nil {
		t.Fatalf("bind queue: %v", err)
	}

	if _, err := channel.QueuePurge(testQueue, false); err != nil {
		t.Fatalf("purge queue: %v", err)
	}

	return database, brokerURL
}

func queuedMessages(t *testing.T, brokerURL string) int {
	t.Helper()

	connection, err := amqp.Dial(brokerURL)
	if err != nil {
		t.Fatalf("connect to the broker: %v", err)
	}
	defer connection.Close()

	channel, err := connection.Channel()
	if err != nil {
		t.Fatalf("open a channel: %v", err)
	}
	defer channel.Close()

	// A passive declare does not change the queue; it only reports on it.
	state, err := channel.QueueDeclarePassive(testQueue, true, false, false, false, nil)
	if err != nil {
		t.Fatalf("inspect queue: %v", err)
	}

	return state.Messages
}

func eventKeys(t *testing.T, database *sql.DB) int {
	t.Helper()

	var count int

	if err := database.QueryRowContext(
		context.Background(),
		"SELECT COUNT(*) FROM published_queue_events",
	).Scan(&count); err != nil {
		t.Fatalf("count event keys: %v", err)
	}

	return count
}

func TestPublisherDeduplicatesEventKey(t *testing.T) {
	database, brokerURL := setup(t)
	ctx := context.Background()

	publisher := Publisher{
		DB:         database,
		URL:        brokerURL,
		Exchange:   testExchange,
		RoutingKey: testRoutingKey,
	}

	if err := publisher.Publish(ctx, testObservations()); err != nil {
		t.Fatalf("first publish: %v", err)
	}

	if err := publisher.Publish(ctx, testObservations()); err != nil {
		t.Fatalf("duplicate publish: %v", err)
	}

	// The broker counts asynchronously; give it a moment before reading.
	time.Sleep(200 * time.Millisecond)

	if got := queuedMessages(t, brokerURL); got != 1 {
		t.Fatalf("expected 1 queued message, got %d", got)
	}

	if got := eventKeys(t, database); got != 1 {
		t.Fatalf("expected 1 event key, got %d", got)
	}
}

func TestPublisherReleasesClaimWhenUnroutable(t *testing.T) {
	database, brokerURL := setup(t)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	publisher := Publisher{
		DB:         database,
		URL:        brokerURL,
		Exchange:   testExchange,
		RoutingKey: "nobody.listens.here",
	}

	if err := publisher.Publish(ctx, testObservations()); err == nil {
		t.Fatal("expected an unroutable publish to fail")
	}

	if got := eventKeys(t, database); got != 0 {
		t.Fatalf("expected the claim to be released, found %d event keys", got)
	}

	if got := queuedMessages(t, brokerURL); got != 0 {
		t.Fatalf("expected no queued message, got %d", got)
	}
}
