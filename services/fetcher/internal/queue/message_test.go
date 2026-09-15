package queue

import (
	"encoding/json"
	"testing"
	"time"

	"oil-price-tracker/fetcher/internal/model"
)

func TestEncodeDerivesKeyFromScheduledSlot(t *testing.T) {
	scheduledFor := time.Date(2026, 8, 18, 12, 0, 0, 0, time.FixedZone("Kyiv", 3*60*60))

	eventKey, body, err := Encode([]model.Observation{{
		InstrumentCode: "WTI_USD_BBL",
		ScheduledFor:   scheduledFor,
	}})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if eventKey != "oil-prices:2026-08-18T09:00:00Z" {
		t.Fatalf("unexpected event key: %s", eventKey)
	}

	var decoded Event

	if err := json.Unmarshal(body, &decoded); err != nil {
		t.Fatalf("decode event: %v", err)
	}

	if decoded.SchemaVersion != 1 || decoded.EventKey != eventKey || len(decoded.Observations) != 1 {
		t.Fatalf("unexpected event: %+v", decoded)
	}
}

func TestEncodeRejectsEmptyBatch(t *testing.T) {
	if _, _, err := Encode(nil); err == nil {
		t.Fatal("expected an error for an empty batch")
	}
}
