package broker

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
	URL        string
	Exchange   string
	Queue      string
	RoutingKey string
}

type batchMessage struct {
	SchemaVersion int                 `json:"schema_version"`
	Observations  []model.Observation `json:"observations"`
}

func (publisher Publisher) Publish(ctx context.Context, observations []model.Observation) error {
	if len(observations) == 0 {
		return fmt.Errorf("cannot publish an empty observation event")
	}
	body, err := json.Marshal(batchMessage{SchemaVersion: 1, Observations: observations})
	if err != nil {
		return fmt.Errorf("encode observation event: %w", err)
	}

	return provider.Retry(ctx, 5, time.Second, func() error {
		return publisher.publishOnce(ctx, observations[0].ScheduledFor, body)
	})
}

func (publisher Publisher) publishOnce(ctx context.Context, slot time.Time, body []byte) error {
	connection, err := amqp.Dial(publisher.URL)
	if err != nil {
		return fmt.Errorf("connect RabbitMQ: %w", err)
	}
	defer connection.Close()

	channel, err := connection.Channel()
	if err != nil {
		return fmt.Errorf("open RabbitMQ channel: %w", err)
	}
	defer channel.Close()

	if err := channel.ExchangeDeclare(
		publisher.Exchange,
		"direct",
		true,
		false,
		false,
		false,
		nil,
	); err != nil {
		return fmt.Errorf("declare exchange: %w", err)
	}
	if _, err := channel.QueueDeclare(
		publisher.Queue,
		true,
		false,
		false,
		false,
		nil,
	); err != nil {
		return fmt.Errorf("declare queue: %w", err)
	}
	if err := channel.QueueBind(
		publisher.Queue,
		publisher.RoutingKey,
		publisher.Exchange,
		false,
		nil,
	); err != nil {
		return fmt.Errorf("bind queue: %w", err)
	}
	if err := channel.Confirm(false); err != nil {
		return fmt.Errorf("enable publisher confirms: %w", err)
	}

	confirms := channel.NotifyPublish(make(chan amqp.Confirmation, 1))
	returns := channel.NotifyReturn(make(chan amqp.Return, 1))
	if err := channel.PublishWithContext(
		ctx,
		publisher.Exchange,
		publisher.RoutingKey,
		true,
		false,
		amqp.Publishing{
			ContentType:  "application/json",
			DeliveryMode: amqp.Persistent,
			MessageId:    "oil-prices:" + slot.UTC().Format(time.RFC3339),
			Timestamp:    time.Now().UTC(),
			Type:         "prices.observed.v1",
			Body:         body,
		},
	); err != nil {
		return fmt.Errorf("publish observation event: %w", err)
	}

	select {
	case returned := <-returns:
		return fmt.Errorf("event was not routed: %s", returned.ReplyText)
	case confirmation := <-confirms:
		if !confirmation.Ack {
			return fmt.Errorf("RabbitMQ negatively acknowledged the event")
		}
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}
