package main

import (
	"bytes"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestAccessLogUsesStructuredSafeFields(t *testing.T) {
	var logs bytes.Buffer
	previous := slog.Default()
	slog.SetDefault(slog.New(slog.NewJSONHandler(&logs, nil)))
	t.Cleanup(func() { slog.SetDefault(previous) })

	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", func(response http.ResponseWriter, _ *http.Request) {
		response.WriteHeader(http.StatusServiceUnavailable)
	})
	request := httptest.NewRequest(http.MethodGet, "/health?token=secret", nil)
	request.Header.Set("Authorization", "Bearer secret")
	request.Header.Set("X-Request-ID", "test-request")
	response := httptest.NewRecorder()

	accessLogMiddleware(mux).ServeHTTP(response, request)

	var entry map[string]any
	if err := json.Unmarshal(logs.Bytes(), &entry); err != nil {
		t.Fatal(err)
	}
	if entry["status"] != float64(http.StatusServiceUnavailable) {
		t.Fatalf("unexpected status: %v", entry["status"])
	}
	if entry["route"] != "GET /health" || entry["request_id"] != "test-request" {
		t.Fatalf("unexpected access fields: %v", entry)
	}
	if bytes.Contains(logs.Bytes(), []byte("secret")) || bytes.Contains(logs.Bytes(), []byte("token")) {
		t.Fatalf("access log leaked request data: %s", logs.String())
	}
}
