package eventstore

import (
	"context"
	"database/sql"
	"database/sql/driver"
	"encoding/json"
	"errors"
	"sync"
	"testing"
	"time"

	"oil-price-tracker/fetcher/internal/model"
)

type fakeResult struct {
	rows int64
}

func (result fakeResult) LastInsertId() (int64, error) {
	return 0, nil
}

func (result fakeResult) RowsAffected() (int64, error) {
	return result.rows, nil
}

type fakeDB struct {
	mu        sync.Mutex
	calls     int
	keys      map[string]bool
	lastKey   string
	lastBody  []byte
	failures  int
	failError error
}

func (db *fakeDB) ExecContext(
	ctx context.Context,
	_ string,
	args ...any,
) (sql.Result, error) {
	db.mu.Lock()
	defer db.mu.Unlock()

	db.calls++

	select {
	case <-ctx.Done():
		return nil, ctx.Err()
	default:
	}

	if db.failures > 0 {
		db.failures--
		return nil, db.failError
	}

	key := args[0].(string)
	body := args[1].([]byte)

	db.lastKey = key
	db.lastBody = append([]byte(nil), body...)

	if db.keys == nil {
		db.keys = make(map[string]bool)
	}

	if db.keys[key] {
		return fakeResult{rows: 0}, nil
	}

	db.keys[key] = true

	return fakeResult{rows: 1}, nil
}

func testObservation() model.Observation {
	return model.Observation{
		InstrumentCode: "WTI_USD_BBL",
		InstrumentName: "WTI Crude Oil",
		Category:       "crude_oil",
		Price:          "75.50",
		Currency:       "USD",
		Unit:           "USD per barrel",
		Source:         "oilpriceapi",
		SourceSeriesID: "WTI_USD",
		SourcePeriod:   "2026-08-16",
		ScheduledFor:   time.Date(2026, 8, 16, 12, 0, 0, 0, time.UTC),
		FetchedAt:      time.Date(2026, 8, 16, 12, 0, 5, 0, time.UTC),
		SourceURL:      "https://example.test",
		RawData:        map[string]any{"value": 75.50},
	}
}

func TestPublisherCreatesEvent(t *testing.T) {
	db := &fakeDB{}

	publisher := Publisher{
		DB:            db,
		RetryAttempts: 1,
	}

	err := publisher.Publish(
		context.Background(),
		[]model.Observation{testObservation()},
	)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if db.calls != 1 {
		t.Fatalf("expected 1 database call, got %d", db.calls)
	}

	expectedKey := "oil-prices:2026-08-16T12:00:00Z"

	if db.lastKey != expectedKey {
		t.Fatalf(
			"unexpected event key: got %q want %q",
			db.lastKey,
			expectedKey,
		)
	}

	var message struct {
		SchemaVersion int                 `json:"schema_version"`
		Observations  []model.Observation `json:"observations"`
	}

	if err := json.Unmarshal(db.lastBody, &message); err != nil {
		t.Fatalf("decode event payload: %v", err)
	}

	if message.SchemaVersion != 1 {
		t.Fatalf(
			"unexpected schema version: %d",
			message.SchemaVersion,
		)
	}

	if len(message.Observations) != 1 {
		t.Fatalf(
			"expected 1 observation, got %d",
			len(message.Observations),
		)
	}
}

func TestPublisherRejectsEmptyBatch(t *testing.T) {
	db := &fakeDB{}

	publisher := Publisher{
		DB: db,
	}

	err := publisher.Publish(context.Background(), nil)

	if err == nil {
		t.Fatal("expected empty batch to be rejected")
	}

	if db.calls != 0 {
		t.Fatalf(
			"database should not be called for empty batch, got %d calls",
			db.calls,
		)
	}
}

func TestPublisherDuplicateEventIsIdempotent(t *testing.T) {
	db := &fakeDB{}

	publisher := Publisher{
		DB:            db,
		RetryAttempts: 1,
	}

	observations := []model.Observation{testObservation()}

	if err := publisher.Publish(context.Background(), observations); err != nil {
		t.Fatalf("first publish failed: %v", err)
	}

	if err := publisher.Publish(context.Background(), observations); err != nil {
		t.Fatalf("duplicate publish failed: %v", err)
	}

	if len(db.keys) != 1 {
		t.Fatalf(
			"expected only one unique event, got %d",
			len(db.keys),
		)
	}
}

func TestPublisherRetriesTransientDatabaseFailure(t *testing.T) {
	db := &fakeDB{
		failures:  2,
		failError: driver.ErrBadConn,
	}

	publisher := Publisher{
		DB:            db,
		RetryAttempts: 3,
		RetryDelay:    time.Millisecond,
	}

	err := publisher.Publish(
		context.Background(),
		[]model.Observation{testObservation()},
	)
	if err != nil {
		t.Fatalf("unexpected error after retry: %v", err)
	}

	if db.calls != 3 {
		t.Fatalf(
			"expected 3 database attempts, got %d",
			db.calls,
		)
	}
}

func TestPublisherReturnsPermanentDatabaseFailure(t *testing.T) {
	expectedError := errors.New("invalid database operation")

	db := &fakeDB{
		failures:  1,
		failError: expectedError,
	}

	publisher := Publisher{
		DB:            db,
		RetryAttempts: 5,
		RetryDelay:    time.Millisecond,
	}

	err := publisher.Publish(
		context.Background(),
		[]model.Observation{testObservation()},
	)

	if err == nil {
		t.Fatal("expected database error")
	}

	if db.calls != 1 {
		t.Fatalf(
			"permanent error should not be retried, got %d calls",
			db.calls,
		)
	}
}

func TestPublisherRespectsCancellation(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	db := &fakeDB{}

	publisher := Publisher{
		DB:            db,
		RetryAttempts: 5,
		RetryDelay:    time.Second,
	}

	err := publisher.Publish(
		ctx,
		[]model.Observation{testObservation()},
	)

	if !errors.Is(err, context.Canceled) {
		t.Fatalf(
			"expected context.Canceled, got %v",
			err,
		)
	}
}
