package rabbitmq

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/url"
	"strconv"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"

	"oil-price-tracker/fetcher/internal/model"
)

type channel interface {
	QueueDeclare(string, bool, bool, bool, bool, amqp.Table) (amqp.Queue, error)
	PublishWithContext(context.Context, string, string, bool, bool, amqp.Publishing) error
	Close() error
}

type Publisher struct {
	connection *amqp.Connection
	channel    channel
	queueName  string
}

func New(host string, port int, user, password, vhost, queueName string) (*Publisher, error) {
	endpoint := url.URL{
		Scheme: "amqp",
		User:   url.UserPassword(user, password),
		Host:   net.JoinHostPort(host, strconv.Itoa(port)),
		Path:   "/" + vhost,
	}
	connection, err := amqp.Dial(endpoint.String())
	if err != nil {
		return nil, fmt.Errorf("connect RabbitMQ: %w", err)
	}
	ch, err := connection.Channel()
	if err != nil {
		_ = connection.Close()
		return nil, fmt.Errorf("open RabbitMQ channel: %w", err)
	}
	publisher := &Publisher{connection: connection, channel: ch, queueName: queueName}
	if _, err := ch.QueueDeclare(queueName, true, false, false, false, nil); err != nil {
		_ = publisher.Close()
		return nil, fmt.Errorf("declare RabbitMQ queue: %w", err)
	}
	return publisher, nil
}

func (publisher *Publisher) Close() error {
	_ = publisher.channel.Close()
	return publisher.connection.Close()
}

func (publisher *Publisher) Publish(ctx context.Context, observations []model.Observation) error {
	if len(observations) == 0 {
		return fmt.Errorf("cannot publish an empty observation event")
	}
	event := struct {
		SchemaVersion int                 `json:"schema_version"`
		EventKey      string              `json:"event_key"`
		Observations  []model.Observation `json:"observations"`
	}{
		SchemaVersion: 1,
		EventKey:      "oil-prices:" + observations[0].ScheduledFor.UTC().Format(time.RFC3339),
		Observations:  observations,
	}
	body, err := json.Marshal(event)
	if err != nil {
		return fmt.Errorf("encode observation event: %w", err)
	}
	return publisher.channel.PublishWithContext(ctx, "", publisher.queueName, false, false, amqp.Publishing{
		ContentType:  "application/json",
		DeliveryMode: amqp.Persistent,
		Body:         body,
	})
}
