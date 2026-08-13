package service

import (
	"context"
	"testing"
	"time"

	"oil-price-tracker/fetcher/internal/model"
)

type stubProvider struct {
	observations []model.Observation
}

func (provider stubProvider) Fetch(
	context.Context,
	[]model.Series,
	time.Time,
) ([]model.Observation, error) {
	return provider.observations, nil
}

type stubPublisher struct {
	published int
}

func (publisher *stubPublisher) Publish(
	_ context.Context,
	observations []model.Observation,
) error {
	publisher.published += len(observations)
	return nil
}

func TestRunPublishesFetchedObservations(t *testing.T) {
	slot := time.Date(2026, 7, 27, 6, 0, 0, 0, time.UTC)
	publisher := &stubPublisher{}
	collector := New(
		stubProvider{observations: []model.Observation{
			{InstrumentCode: "WTI_USD_BBL", ScheduledFor: slot},
			{InstrumentCode: "BRENT_USD_BBL", ScheduledFor: slot},
		}},
		publisher,
	)

	result, err := collector.Run(context.Background(), slot)
	if err != nil {
		t.Fatalf("unexpected collection error: %v", err)
	}
	if result.Published != 2 || publisher.published != 2 {
		t.Fatalf("unexpected publish result: %+v, publisher=%d", result, publisher.published)
	}
}
