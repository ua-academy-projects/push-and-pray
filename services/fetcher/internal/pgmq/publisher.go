package pgmq

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"oil-price-tracker/fetcher/internal/model"
	"oil-price-tracker/fetcher/internal/provider"
)

type Publisher struct {
	DB        *sql.DB
	QueueName string
}

type batchMessage struct {
	SchemaVersion int                 `json:"schema_version"`
	EventKey      string              `json:"event_key"`
	Observations  []model.Observation `json:"observations"`
}

func (publisher Publisher) Publish(
	ctx context.Context,
	observations []model.Observation,
) error {
	if len(observations) == 0 {
		return fmt.Errorf(
			"cannot publish an empty observation event",
		)
	}

	eventKey := "oil-prices:" +
		observations[0].
			ScheduledFor.
			UTC().
			Format(time.RFC3339)

	body, err := json.Marshal(
		batchMessage{
			SchemaVersion: 1,
			EventKey:      eventKey,
			Observations:  observations,
		},
	)
	if err != nil {
		return fmt.Errorf(
			"encode observation event: %w",
			err,
		)
	}

	return provider.Retry(
		ctx,
		5,
		time.Second,
		func() error {
			return publisher.publishOnce(
				ctx,
				eventKey,
				body,
			)
		},
	)
}

func (publisher Publisher) publishOnce(
	ctx context.Context,
	eventKey string,
	body []byte,
) error {
	tx, err := publisher.DB.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf(
			"begin publish transaction: %w",
			err,
		)
	}

	defer func() {
		_ = tx.Rollback()
	}()

	var claimedEventKey string

	err = tx.QueryRowContext(
		ctx,
		`
		INSERT INTO published_queue_events (
			event_key
		)
		VALUES ($1)
		ON CONFLICT (event_key) DO NOTHING
		RETURNING event_key
		`,
		eventKey,
	).Scan(&claimedEventKey)

	if errors.Is(err, sql.ErrNoRows) {
		if err := tx.Commit(); err != nil {
			return fmt.Errorf(
				"commit duplicate publish: %w",
				err,
			)
		}

		return nil
	}

	if err != nil {
		return fmt.Errorf(
			"claim event key: %w",
			err,
		)
	}

	var messageID int64

	err = tx.QueryRowContext(
		ctx,
		`
		SELECT *
		FROM pgmq.send(
			queue_name => $1,
			msg => $2::jsonb
		)
		`,
		publisher.QueueName,
		body,
	).Scan(&messageID)

	if err != nil {
		return fmt.Errorf(
			"publish PGMQ message: %w",
			err,
		)
	}

	if err := tx.Commit(); err != nil {
		return fmt.Errorf(
			"commit PGMQ publish: %w",
			err,
		)
	}

	return nil
}
