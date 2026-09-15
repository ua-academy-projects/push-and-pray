package queue

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"oil-price-tracker/fetcher/internal/model"
)

// Event is the message every queue backend carries. The history service
// validates it against one schema no matter which broker delivered it, so the
// PGMQ and AMQP publishers must encode it identically.
type Event struct {
	SchemaVersion int                 `json:"schema_version"`
	EventKey      string              `json:"event_key"`
	Observations  []model.Observation `json:"observations"`
}

// Encode builds the event for one collection run. The key is derived from the
// slot the observations were scheduled for, so a rerun of the same slot claims
// the same key and is dropped as a duplicate instead of being delivered twice.
func Encode(observations []model.Observation) (string, []byte, error) {
	if len(observations) == 0 {
		return "", nil, fmt.Errorf("cannot publish an empty observation event")
	}

	eventKey := "oil-prices:" + observations[0].ScheduledFor.UTC().Format(time.RFC3339)

	body, err := json.Marshal(Event{
		SchemaVersion: 1,
		EventKey:      eventKey,
		Observations:  observations,
	})
	if err != nil {
		return "", nil, fmt.Errorf("encode observation event: %w", err)
	}

	return eventKey, body, nil
}

// Querier is what the claim needs from the database: *sql.DB when the claim is
// its own transaction, *sql.Tx when it shares one with the publish.
type Querier interface {
	QueryRowContext(ctx context.Context, query string, args ...any) *sql.Row
	ExecContext(ctx context.Context, query string, args ...any) (sql.Result, error)
}

// Claim records the event key in published_queue_events. It reports false when
// the key is already there, which means an earlier run published this event.
func Claim(ctx context.Context, db Querier, eventKey string) (bool, error) {
	var claimedEventKey string

	err := db.QueryRowContext(
		ctx,
		`
		INSERT INTO published_queue_events (event_key)
		VALUES ($1)
		ON CONFLICT (event_key) DO NOTHING
		RETURNING event_key
		`,
		eventKey,
	).Scan(&claimedEventKey)

	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}

	if err != nil {
		return false, fmt.Errorf("claim event key: %w", err)
	}

	return true, nil
}

// Release gives a claim back after the publish it guarded has failed, so the
// next attempt is not mistaken for a duplicate.
func Release(ctx context.Context, db Querier, eventKey string) error {
	if _, err := db.ExecContext(
		ctx,
		`DELETE FROM published_queue_events WHERE event_key = $1`,
		eventKey,
	); err != nil {
		return fmt.Errorf("release event key: %w", err)
	}

	return nil
}
