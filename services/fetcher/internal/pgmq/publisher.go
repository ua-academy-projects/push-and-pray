package pgmq

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"oil-price-tracker/fetcher/internal/model"
	"oil-price-tracker/fetcher/internal/provider"
	"oil-price-tracker/fetcher/internal/queue"
)

type Publisher struct {
	DB        *sql.DB
	QueueName string
}

func (publisher Publisher) Publish(
	ctx context.Context,
	observations []model.Observation,
) error {
	eventKey, body, err := queue.Encode(observations)
	if err != nil {
		return err
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

// publishOnce claims the event key and sends the message in one transaction:
// either both land or neither does, so a message is published exactly once.
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

	claimed, err := queue.Claim(ctx, tx, eventKey)
	if err != nil {
		return err
	}

	if !claimed {
		if err := tx.Commit(); err != nil {
			return fmt.Errorf(
				"commit duplicate publish: %w",
				err,
			)
		}

		return nil
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
