// Package amqp publishes observation events to a RabbitMQ exchange. It is the
// queue backend for deployments whose PostgreSQL has no PGMQ extension - the
// managed services offer none - and is chosen with QUEUE_BACKEND=amqp.
package amqp

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"

	"oil-price-tracker/fetcher/internal/model"
	"oil-price-tracker/fetcher/internal/provider"
	"oil-price-tracker/fetcher/internal/queue"
)

// Publisher sends every event to one topic exchange. The queue behind it is
// declared by the history service, which owns the consumer side of the
// topology; publishing is mandatory, so an event with nowhere to go fails
// here instead of vanishing.
type Publisher struct {
	// DB holds published_queue_events, the ledger that keeps a slot from being
	// published twice. In this backend it lives in the application database,
	// not next to the messages.
	DB         *sql.DB
	URL        string
	Exchange   string
	RoutingKey string
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
			return publisher.publishOnce(ctx, eventKey, body)
		},
	)
}

// publishOnce claims the key first and publishes second. Unlike PGMQ the two
// cannot share a transaction, so the claim is released again when the broker
// refuses the message - which narrows the window for a lost event rather
// than closing it. A crash between the two drops one batch; the next
// scheduled run collects those prices again.
func (publisher Publisher) publishOnce(
	ctx context.Context,
	eventKey string,
	body []byte,
) error {
	claimed, err := queue.Claim(ctx, publisher.DB, eventKey)
	if err != nil {
		return err
	}

	if !claimed {
		return nil
	}

	if err := publisher.send(ctx, body); err != nil {
		if releaseErr := queue.Release(ctx, publisher.DB, eventKey); releaseErr != nil {
			return fmt.Errorf("%w (and %v)", err, releaseErr)
		}

		return err
	}

	return nil
}

func (publisher Publisher) send(ctx context.Context, body []byte) error {
	connection, err := amqp.Dial(publisher.URL)
	if err != nil {
		return fmt.Errorf("connect to the broker: %w", err)
	}
	defer connection.Close()

	channel, err := connection.Channel()
	if err != nil {
		return fmt.Errorf("open a broker channel: %w", err)
	}
	defer channel.Close()

	if err := channel.Confirm(false); err != nil {
		return fmt.Errorf("enable publisher confirms: %w", err)
	}

	if err := channel.ExchangeDeclare(
		publisher.Exchange,
		"topic",
		true,  // durable
		false, // auto-delete
		false, // internal
		false, // no-wait
		nil,
	); err != nil {
		return fmt.Errorf("declare exchange %q: %w", publisher.Exchange, err)
	}

	// A mandatory publish that no queue accepts comes back as a basic.return,
	// which the broker sends before the confirm for the same message.
	returns := channel.NotifyReturn(make(chan amqp.Return, 1))

	confirmation, err := channel.PublishWithDeferredConfirmWithContext(
		ctx,
		publisher.Exchange,
		publisher.RoutingKey,
		true,  // mandatory
		false, // immediate
		amqp.Publishing{
			ContentType:  "application/json",
			DeliveryMode: amqp.Persistent,
			Timestamp:    time.Now().UTC(),
			Body:         body,
		},
	)
	if err != nil {
		return fmt.Errorf("publish AMQP message: %w", err)
	}

	acked, err := confirmation.WaitContext(ctx)
	if err != nil {
		return fmt.Errorf("wait for the broker to confirm: %w", err)
	}

	select {
	case returned := <-returns:
		return fmt.Errorf(
			"the broker returned the message: %s (no queue is bound to %q with key %q)",
			returned.ReplyText,
			publisher.Exchange,
			publisher.RoutingKey,
		)
	default:
	}

	if !acked {
		return fmt.Errorf("the broker did not confirm the message")
	}

	return nil
}
