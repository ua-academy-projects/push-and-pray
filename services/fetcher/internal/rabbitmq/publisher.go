package rabbitmq

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"

	"oil-price-tracker/fetcher/internal/model"
	"oil-price-tracker/fetcher/internal/provider"
)

type Publisher struct {
	URL       string
	QueueName string
}

type batchMessage struct {
	SchemaVersion int                 `json:"schema_version"`
	EventKey      string              `json:"event_key"`
	Observations  []model.Observation `json:"observations"`
}

func (publisher Publisher) Publish(ctx context.Context, observations []model.Observation) error {
	if len(observations) == 0 {
		return fmt.Errorf("cannot publish an empty observation event")
	}

	eventKey := "oil-prices:" + observations[0].ScheduledFor.UTC().Format(time.RFC3339)
	body, err := json.Marshal(batchMessage{
		SchemaVersion: 1,
		EventKey:      eventKey,
		Observations:  observations,
	})
	if err != nil {
		return fmt.Errorf("encode observation event: %w", err)
	}

	return provider.Retry(ctx, 5, time.Second, func() error {
		return publisher.publishOnce(ctx, eventKey, body)
	})
}

func (publisher Publisher) publishOnce(ctx context.Context, eventKey string, body []byte) error {
	connection, err := amqp.Dial(publisher.URL)
	if err != nil {
		return fmt.Errorf("connect to RabbitMQ: %w", err)
	}
	defer connection.Close()

	channel, err := connection.Channel()
	if err != nil {
		return fmt.Errorf("open RabbitMQ channel: %w", err)
	}
	defer channel.Close()

	deadLetterExchange := publisher.QueueName + ".dead-letter"
	if err := channel.ExchangeDeclare(
		deadLetterExchange, "direct", true, false, false, false, nil,
	); err != nil {
		return fmt.Errorf("declare RabbitMQ dead-letter exchange: %w", err)
	}
	if _, err := channel.QueueDeclare(
		publisher.QueueName,
		true,
		false,
		false,
		false,
		amqp.Table{"x-dead-letter-exchange": deadLetterExchange},
	); err != nil {
		return fmt.Errorf("declare RabbitMQ queue: %w", err)
	}
	if err := channel.Confirm(false); err != nil {
		return fmt.Errorf("enable RabbitMQ publisher confirms: %w", err)
	}

	confirmation := channel.NotifyPublish(make(chan amqp.Confirmation, 1))
	if err := channel.PublishWithContext(ctx, "", publisher.QueueName, true, false, amqp.Publishing{
		ContentType:  "application/json",
		DeliveryMode: amqp.Persistent,
		MessageId:    eventKey,
		Timestamp:    time.Now().UTC(),
		Body:         body,
	}); err != nil {
		return fmt.Errorf("publish RabbitMQ message: %w", err)
	}

	select {
	case result := <-confirmation:
		if !result.Ack {
			return fmt.Errorf("RabbitMQ rejected published message")
		}
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}
