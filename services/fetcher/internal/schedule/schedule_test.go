package schedule

import (
	"testing"
	"time"
)

func TestLatestSlot(t *testing.T) {
	now := time.Date(2026, time.July, 22, 13, 15, 0, 0, time.UTC)
	got := LatestSlot(now, []int{0, 6, 12, 18}, time.UTC)
	want := time.Date(2026, time.July, 22, 12, 0, 0, 0, time.UTC)
	if !got.Equal(want) {
		t.Fatalf("LatestSlot() = %s, want %s", got, want)
	}
}

func TestLatestSlotWrapsToPreviousDay(t *testing.T) {
	now := time.Date(2026, time.July, 22, 0, 30, 0, 0, time.UTC)
	got := LatestSlot(now, []int{1, 7, 13, 19}, time.UTC)
	want := time.Date(2026, time.July, 21, 19, 0, 0, 0, time.UTC)
	if !got.Equal(want) {
		t.Fatalf("LatestSlot() = %s, want %s", got, want)
	}
}

func TestNextSlot(t *testing.T) {
	now := time.Date(2026, time.July, 22, 18, 0, 0, 0, time.UTC)
	got := NextSlot(now, []int{0, 6, 12, 18}, time.UTC)
	want := time.Date(2026, time.July, 23, 0, 0, 0, 0, time.UTC)
	if !got.Equal(want) {
		t.Fatalf("NextSlot() = %s, want %s", got, want)
	}
}
