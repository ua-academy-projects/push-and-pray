package provider

import (
	"encoding/json"
	"testing"
	"time"

	"oil-price-tracker/fetcher/internal/model"
)

func TestParseOilPriceResponse(t *testing.T) {
	slot := time.Date(2026, time.July, 27, 6, 0, 0, 0, time.UTC)
	payload := json.RawMessage(`{
		"prices": [
			{
				"code": "WTI_USD",
				"price": 68.42,
				"currency": "USD",
				"unit": "barrel",
				"observed_at": "2026-07-27T05:59:00Z",
				"source": "market_reporting",
				"metadata": {"source_description": "Market reporting"}
			}
		],
		"metadata": {"timestamp": "2026-07-27T06:00:01Z"}
	}`)

	observations, err := ParseOilPriceResponse(
		payload,
		model.TrackedSeries[:1],
		slot,
		slot.Add(2*time.Second),
		"https://example.test",
	)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	observation := observations[0]
	if observation.Price != "68.42" || observation.SourcePeriod != "2026-07-27" {
		t.Fatalf("unexpected observation: %+v", observation)
	}
	if !observation.SourceObservedAt.Equal(time.Date(2026, 7, 27, 5, 59, 0, 0, time.UTC)) {
		t.Fatalf("unexpected source timestamp: %s", observation.SourceObservedAt)
	}
}

func TestParseOilPriceResponseRejectsMissingSeries(t *testing.T) {
	payload := json.RawMessage(`{"prices":[{"code":"WTI_USD","price":68.42,
		"created_at":"2026-07-27T06:00:00Z"}]}`)
	if _, err := ParseOilPriceResponse(
		payload,
		model.TrackedSeries[:2],
		time.Now(),
		time.Now(),
		"test",
	); err == nil {
		t.Fatal("expected missing series error")
	}
}

func TestParseOilPriceResponseAcceptsPriceArray(t *testing.T) {
	payload := json.RawMessage(`[{"code":"WTI_USD","price":68.42,
		"created_at":"2026-07-27T06:00:00Z"}]`)
	observations, err := ParseOilPriceResponse(
		payload,
		model.TrackedSeries[:1],
		time.Now(),
		time.Now(),
		"test",
	)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if observations[0].Price != "68.42" {
		t.Fatalf("unexpected observation: %+v", observations[0])
	}
}

func TestParseOilPriceResponseRejectsInvalidPrice(t *testing.T) {
	payload := json.RawMessage(`{"prices":[{"code":"WTI_USD","price":-1,
		"created_at":"2026-07-27T06:00:00Z"}]}`)
	if _, err := ParseOilPriceResponse(
		payload,
		model.TrackedSeries[:1],
		time.Now(),
		time.Now(),
		"test",
	); err == nil {
		t.Fatal("expected invalid price error")
	}
}
