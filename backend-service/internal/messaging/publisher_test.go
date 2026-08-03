package messaging

import (
	"encoding/json"
	"testing"
)

func TestBackfillCommandContract(t *testing.T) {
	command := BackfillCommand{
		CommandID: "command-1", CommandType: "rates.backfill.requested", Schema: 1,
		RequestID: "request-1", Instrument: "crypto:bitcoin:usd",
		From: "2026-01-01T00:00:00Z", To: "2026-07-29T00:00:00Z",
	}
	payload, err := json.Marshal(command)
	if err != nil {
		t.Fatal(err)
	}
	var decoded map[string]any
	if err := json.Unmarshal(payload, &decoded); err != nil {
		t.Fatal(err)
	}
	if decoded["instrument_id"] != command.Instrument || decoded["command_type"] != command.CommandType {
		t.Fatalf("unexpected command payload: %s", payload)
	}
}
