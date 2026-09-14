package httplog

import (
	"bytes"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
)

func captureLogs(t *testing.T) *bytes.Buffer {
	t.Helper()

	var buffer bytes.Buffer

	previous := slog.Default()
	slog.SetDefault(slog.New(slog.NewJSONHandler(&buffer, nil)))
	t.Cleanup(func() { slog.SetDefault(previous) })

	return &buffer
}

func TestHandlerLogsRequestFields(t *testing.T) {
	logs := captureLogs(t)

	handler := Handler(http.HandlerFunc(func(
		response http.ResponseWriter,
		_ *http.Request,
	) {
		response.WriteHeader(http.StatusConflict)
	}))

	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, httptest.NewRequest(http.MethodPost, "/v1/fetch", nil))

	var entry map[string]any
	if err := json.Unmarshal(logs.Bytes(), &entry); err != nil {
		t.Fatalf("log line is not JSON: %v: %q", err, logs.String())
	}

	if entry["method"] != http.MethodPost || entry["path"] != "/v1/fetch" {
		t.Fatalf("unexpected request fields: %v", entry)
	}

	if entry["status"] != float64(http.StatusConflict) {
		t.Fatalf("status = %v, want %d", entry["status"], http.StatusConflict)
	}

	if _, ok := entry["duration_ms"]; !ok {
		t.Fatalf("duration_ms missing: %v", entry)
	}
}

func TestHandlerSkipsHealthProbe(t *testing.T) {
	logs := captureLogs(t)

	handler := Handler(http.HandlerFunc(func(
		response http.ResponseWriter,
		_ *http.Request,
	) {
		response.WriteHeader(http.StatusOK)
	}))

	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, HealthPath, nil))

	if recorder.Code != http.StatusOK {
		t.Fatalf("health probe status = %d, want %d", recorder.Code, http.StatusOK)
	}

	if logs.Len() != 0 {
		t.Fatalf("health probe was logged: %q", logs.String())
	}
}

func TestHandlerDefaultsToOKWhenHandlerWritesNoHeader(t *testing.T) {
	logs := captureLogs(t)

	handler := Handler(http.HandlerFunc(func(
		response http.ResponseWriter,
		_ *http.Request,
	) {
		_, _ = response.Write([]byte("{}"))
	}))

	handler.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/v1/x", nil))

	var entry map[string]any
	if err := json.Unmarshal(logs.Bytes(), &entry); err != nil {
		t.Fatalf("log line is not JSON: %v", err)
	}

	if entry["status"] != float64(http.StatusOK) {
		t.Fatalf("status = %v, want %d", entry["status"], http.StatusOK)
	}
}
