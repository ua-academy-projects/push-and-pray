package rabbitmq

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"

	"oil-price-tracker/fetcher/internal/model"
)

type fakeChannel struct {
	published amqp.Publishing
	key       string
}

func (fake *fakeChannel) QueueDeclare(string, bool, bool, bool, bool, amqp.Table) (amqp.Queue, error) {
	return amqp.Queue{}, nil
}
func (fake *fakeChannel) PublishWithContext(_ context.Context, _, key string, _, _ bool, message amqp.Publishing) error {
	fake.key = key
	fake.published = message
	return nil
}
func (fake *fakeChannel) Close() error { return nil }

func TestPublishUsesDurableQueueMessageAndPreservesSchema(t *testing.T) {
	channel := &fakeChannel{}
	publisher := &Publisher{channel: channel, queueName: "prices"}
	scheduled := time.Date(2026, 7, 27, 6, 0, 0, 0, time.UTC)
	err := publisher.Publish(context.Background(), []model.Observation{{ScheduledFor: scheduled}})
	if err != nil {
		t.Fatalf("Publish returned error: %v", err)
	}
	if channel.key != "prices" || channel.published.DeliveryMode != amqp.Persistent {
		t.Fatal("message was not published persistently to the durable queue")
	}
	var body map[string]any
	if err := json.Unmarshal(channel.published.Body, &body); err != nil {
		t.Fatalf("invalid JSON payload: %v", err)
	}
	if body["schema_version"] != float64(1) || body["event_key"] != "oil-prices:2026-07-27T06:00:00Z" {
		t.Fatalf("unexpected event envelope: %#v", body)
	}
}
