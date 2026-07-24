package messaging

import (
	"context"
	"encoding/json"
	"log"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"

	"rateboard/api-fetcher/internal/repository"
)

type Consumer struct {
	URL        string
	Exchange   string
	Queue      string
	RoutingKey string
	Store      *repository.Store
}

type event struct {
	EventID        string                 `json:"event_id"`
	RequestID      string                 `json:"request_id"`
	IdempotencyKey string                 `json:"idempotency_key"`
	Observation    repository.Observation `json:"observation"`
}

func (c *Consumer) Run(ctx context.Context) {
	for ctx.Err() == nil {
		if err := c.consume(ctx); err != nil && ctx.Err() == nil {
			log.Printf(`{"service":"api-fetcher","event":"rabbitmq_consumer_error","error":%q}`, err.Error())
			select {
			case <-ctx.Done():
				return
			case <-time.After(2 * time.Second):
			}
		}
	}
}

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
	deliveries, err := channel.ConsumeWithContext(ctx, c.Queue, "api-fetcher", false, false, false, false, nil)
	if err != nil {
		return err
	}
	log.Printf(`{"service":"api-fetcher","event":"rabbitmq_consumer_ready","queue":%q}`, c.Queue)
	for delivery := range deliveries {
		c.handle(ctx, delivery)
	}
	return nil
}

func (c *Consumer) handle(ctx context.Context, delivery amqp.Delivery) {
	var message event
	if err := json.Unmarshal(delivery.Body, &message); err != nil || message.EventID == "" {
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
