package main

import (
	"regexp"
	"testing"
)

func TestNewUUIDMatchesDatabaseUUIDFormat(t *testing.T) {
	value := newUUID()
	if !regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`).MatchString(value) {
		t.Fatalf("unexpected UUID: %s", value)
	}
}
