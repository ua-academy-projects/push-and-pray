package repository

import (
	"testing"
	"time"
)

func TestValidObservationRequiresDatabaseFields(t *testing.T) {
	item := Observation{
		InstrumentID: "crypto:bitcoin:usd",
		Kind:         "crypto", Base: "BTC", Quote: "USD", Name: "Bitcoin",
		Price: "64000.12", Source: "coingecko",
		SourceTimestamp: time.Now().UTC(), RequestedAt: time.Now().UTC(),
		RequestID: "00000000-0000-0000-0000-000000000001",
	}
	if !Valid(item) {
		t.Fatal("complete observation should be valid")
	}
	item.Price = ""
	if Valid(item) {
		t.Fatal("observation without price should be invalid")
	}
}
