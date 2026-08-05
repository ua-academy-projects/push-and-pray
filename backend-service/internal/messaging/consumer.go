package messaging

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"sync/atomic"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"

	"rateboard/backend-service/internal/repository"
)

type Consumer struct {
	URL        string
	Exchange   string
	Queue      string
	RoutingKey string
	Store      *repository.Store
	ready      atomic.Bool
}

type event struct {
	EventID        string                 `json:"event_id"`
	EventType      string                 `json:"event_type"`
	SchemaVersion  int                    `json:"schema_version"`
	RequestID      string                 `json:"request_id"`
	IdempotencyKey string                 `json:"idempotency_key"`
	Observation    repository.Observation `json:"observation"`
}

func (c *Consumer) Run(ctx context.Context) {
	for ctx.Err() == nil {
		if err := c.consume(ctx); err != nil && ctx.Err() == nil {
			slog.Error("RabbitMQ consumer failed", "service", "history-service", "event", "rabbitmq_consumer_error", "error_type", fmt.Sprintf("%T", err))
			select {
			case <-ctx.Done():
				return
			case <-time.After(2 * time.Second):
			}
		}
	}
}

func (c *Consumer) Ready() bool { return c.ready.Load() }

func (c *Consumer) consume(ctx context.Context) error {
	connection, err := amqp.Dial(c.URL)
	if err != nil {
		return err
	}
	defer connection.Close()
	channel, err := connection.Channel()
	if err != nil {
		return err
	}
	defer channel.Close()
	defer c.ready.Store(false)

	dlx := c.Exchange + ".dlx"
	dlq := c.Queue + ".dlq"
	if err = channel.ExchangeDeclare(c.Exchange, "direct", true, false, false, false, nil); err != nil {
		return err
	}
	if err = channel.ExchangeDeclare(dlx, "direct", true, false, false, false, nil); err != nil {
		return err
	}
	if _, err = channel.QueueDeclare(dlq, true, false, false, false, nil); err != nil {
		return err
	}
	if err = channel.QueueBind(dlq, c.Queue, dlx, false, nil); err != nil {
		return err
	}
	arguments := amqp.Table{"x-dead-letter-exchange": dlx, "x-dead-letter-routing-key": c.Queue}
	if _, err = channel.QueueDeclare(c.Queue, true, false, false, false, arguments); err != nil {
		return err
	}
	if err = channel.QueueBind(c.Queue, c.RoutingKey, c.Exchange, false, nil); err != nil {
		return err
	}
	if err = channel.Qos(10, 0, false); err != nil {
		return err
	}
	deliveries, err := channel.ConsumeWithContext(ctx, c.Queue, "backend-service", false, false, false, false, nil)
	if err != nil {
		return err
	}
	slog.Info("RabbitMQ consumer ready", "service", "history-service", "event", "rabbitmq_consumer_ready", "queue", c.Queue)
	c.ready.Store(true)
	for delivery := range deliveries {
		c.handle(ctx, delivery)
	}
	return nil
}

func (c *Consumer) handle(ctx context.Context, delivery amqp.Delivery) {
	var message event
	if err := json.Unmarshal(delivery.Body, &message); err != nil ||
		message.EventID == "" ||
		message.EventType != "rate.observation.collected" ||
		message.SchemaVersion != 1 {
		_ = delivery.Reject(false)
		return
	}
	message.Observation.RequestID = message.RequestID
	if !repository.Valid(message.Observation) {
		_ = delivery.Reject(false)
		return
	}
	if _, err := c.Store.Insert(ctx, message.Observation); err != nil {
		if delivery.Redelivered {
			_ = delivery.Reject(false)
		} else {
			_ = delivery.Nack(false, true)
		}
		return
	}
	_ = delivery.Ack(false)
}
