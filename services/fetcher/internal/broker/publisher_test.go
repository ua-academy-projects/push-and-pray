package broker

import (
	"context"
	"testing"
)

func TestPublisherRejectsEmptyEventWithoutConnecting(t *testing.T) {
	publisher := Publisher{}
	if err := publisher.Publish(context.Background(), nil); err == nil {
		t.Fatal("expected an empty event to be rejected")
	}
}
