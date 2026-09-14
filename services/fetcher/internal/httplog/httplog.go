// Package httplog records one structured log line per HTTP request.
package httplog

import (
	"log/slog"
	"net/http"
	"time"
)

// HealthPath is the probe the container runtime calls every few seconds. It
// carries no information, so it is the one request that is not logged.
const HealthPath = "/health"

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (recorder *statusRecorder) WriteHeader(status int) {
	recorder.status = status
	recorder.ResponseWriter.WriteHeader(status)
}

// Handler wraps next so that every request except the health probe is logged
// with what a request log needs to be searchable: method, path, status,
// duration and the client address.
func Handler(next http.Handler) http.Handler {
	return http.HandlerFunc(func(
		response http.ResponseWriter,
		request *http.Request,
	) {
		if request.URL.Path == HealthPath {
			next.ServeHTTP(response, request)
			return
		}

		started := time.Now()
		recorder := &statusRecorder{
			ResponseWriter: response,
			status:         http.StatusOK,
		}

		next.ServeHTTP(recorder, request)

		slog.Info(
			"http request",
			"method", request.Method,
			"path", request.URL.Path,
			"status", recorder.status,
			"duration_ms", time.Since(started).Milliseconds(),
			"client", request.RemoteAddr,
		)
	})
}
