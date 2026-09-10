package pubsub

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	cloudpubsub "cloud.google.com/go/pubsub"
	"oil-price-tracker/fetcher/internal/model"
)

type Publisher struct{ topic *cloudpubsub.Topic }
type batchMessage struct {
	SchemaVersion int                 `json:"schema_version"`
	EventKey      string              `json:"event_key"`
	Observations  []model.Observation `json:"observations"`
}

func New(projectID, topicID string) (Publisher, error) {
	client, err := cloudpubsub.NewClient(context.Background(), projectID)
	if err != nil {
		return Publisher{}, fmt.Errorf("create Pub/Sub client: %w", err)
	}
	return Publisher{topic: client.Topic(topicID)}, nil
}

func (publisher Publisher) Publish(ctx context.Context, observations []model.Observation) error {
	if len(observations) == 0 {
		return fmt.Errorf("cannot publish an empty observation event")
	}
	eventKey := "oil-prices:" + observations[0].ScheduledFor.UTC().Format(time.RFC3339)
	body, err := json.Marshal(batchMessage{SchemaVersion: 1, EventKey: eventKey, Observations: observations})
	if err != nil {
		return fmt.Errorf("encode observation event: %w", err)
	}
	_, err = publisher.topic.Publish(ctx, &cloudpubsub.Message{Data: body, Attributes: map[string]string{"event_key": eventKey}}).Get(ctx)
	if err != nil {
		return fmt.Errorf("publish Pub/Sub message: %w", err)
	}
	return nil
}
