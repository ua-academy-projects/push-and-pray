package eventstore

import (
	"context"
	"database/sql"
	"database/sql/driver"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"strings"
	"time"

	"oil-price-tracker/fetcher/internal/model"
)

const insertEventSQL = `
INSERT INTO price_events (event_key, payload)
VALUES ($1, $2::jsonb)
ON CONFLICT (event_key) DO NOTHING
`

type DB interface {
	ExecContext(context.Context, string, ...any) (sql.Result, error)
}

type Publisher struct {
	DB            DB
	RetryAttempts int
	RetryDelay    time.Duration
}

type batchMessage struct {
	SchemaVersion int                 `json:"schema_version"`
	Observations  []model.Observation `json:"observations"`
}

func (publisher Publisher) Publish(ctx context.Context, observations []model.Observation) error {
	if len(observations) == 0 {
		return fmt.Errorf("cannot publish an empty observation event")
	}

	body, err := json.Marshal(batchMessage{
		SchemaVersion: 1,
		Observations:  observations,
	})
	if err != nil {
		return fmt.Errorf("encode observation event: %w", err)
	}

	eventKey := "oil-prices:" + observations[0].ScheduledFor.UTC().Format(time.RFC3339)

	attempts := publisher.RetryAttempts
	if attempts <= 0 {
		attempts = 5
	}

	delay := publisher.RetryDelay
	if delay <= 0 {
		delay = time.Second
	}

	var lastErr error

	for attempt := 1; attempt <= attempts; attempt++ {
		_, err := publisher.DB.ExecContext(
			ctx,
			insertEventSQL,
			eventKey,
			body,
		)
		if err == nil {
			return nil
		}

		lastErr = err

		if ctx.Err() != nil {
			return ctx.Err()
		}

		if !isTransient(err) {
			return fmt.Errorf("insert price event: %w", err)
		}

		if attempt == attempts {
			break
		}

		timer := time.NewTimer(delay)

		select {
		case <-ctx.Done():
			timer.Stop()
			return ctx.Err()

		case <-timer.C:
		}
	}

	return fmt.Errorf(
		"insert price event after %d attempts: %w",
		attempts,
		lastErr,
	)
}

func isTransient(err error) bool {
	if errors.Is(err, driver.ErrBadConn) {
		return true
	}

	var networkError net.Error
	if errors.As(err, &networkError) {
		return true
	}

	var sqlStateError interface {
		SQLState() string
	}

	if errors.As(err, &sqlStateError) {
		state := sqlStateError.SQLState()

		if strings.HasPrefix(state, "08") ||
			strings.HasPrefix(state, "40") ||
			strings.HasPrefix(state, "53") {
			return true
		}

		switch state {
		case "57P01", "57P02", "57P03":
			return true
		}
	}

	return false
}
