package api

import (
	"encoding/json"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"rateboard/history-service/internal/repository"
)

type Server struct {
	Store *repository.Store
	Token string
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health/live", s.live)
	mux.HandleFunc("GET /health/ready", s.ready)
	mux.Handle("POST /internal/v1/observations", s.authorize(http.HandlerFunc(s.create)))
	mux.Handle("POST /internal/v1/observations/batch", s.authorize(http.HandlerFunc(s.batch)))
	mux.Handle("GET /internal/v1/observations", s.authorize(http.HandlerFunc(s.list)))
	mux.Handle("GET /internal/v1/series", s.authorize(http.HandlerFunc(s.series)))
	return s.logging(mux)
}

func (s *Server) series(w http.ResponseWriter, r *http.Request) {
	steps := map[string]string{"5m": "5 minutes", "30m": "30 minutes", "1h": "1 hour", "4h": "4 hours", "1d": "1 day"}
	step, ok := steps[r.URL.Query().Get("step")]
	from, fromErr := time.Parse(time.RFC3339, r.URL.Query().Get("from"))
	to, toErr := time.Parse(time.RFC3339, r.URL.Query().Get("to"))
	instruments := strings.Split(r.URL.Query().Get("instruments"), ",")
	if !ok || fromErr != nil || toErr != nil || len(instruments) < 1 || len(instruments) > 5 || from.After(to) {
		writeJSON(w, 400, map[string]any{"error": "invalid series query"})
		return
	}
	for index := range instruments {
		instruments[index] = strings.TrimSpace(instruments[index])
		if instruments[index] == "" {
			writeJSON(w, 400, map[string]any{"error": "invalid series query"})
			return
		}
	}
	series, err := s.Store.Series(r.Context(), instruments, from, to, step)
	if err != nil {
		writeJSON(w, 500, map[string]any{"error": "database read failed"})
		return
	}
	writeJSON(w, 200, map[string]any{"series": series})
}

func (s *Server) live(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, 200, map[string]any{"status": "ok", "service": "history"})
}

func (s *Server) ready(w http.ResponseWriter, r *http.Request) {
	if err := s.Store.Ping(r.Context()); err != nil {
		writeJSON(w, 503, map[string]any{"status": "not_ready", "database": false})
		return
	}
	writeJSON(w, 200, map[string]any{"status": "ready", "database": true})
}

func (s *Server) create(w http.ResponseWriter, r *http.Request) {
	var item repository.Observation
	if err := decode(r, &item); err != nil || !valid(item) {
		writeJSON(w, 400, map[string]any{"error": "invalid observation"})
		return
	}
	created, err := s.Store.Insert(r.Context(), item)
	if err != nil {
		writeJSON(w, 500, map[string]any{"error": "database write failed"})
		return
	}
	writeJSON(w, map[bool]int{true: 201, false: 200}[created], map[string]any{"created": created})
}

func (s *Server) batch(w http.ResponseWriter, r *http.Request) {
	var payload struct {
		Items []repository.Observation `json:"items"`
	}
	if err := decode(r, &payload); err != nil || len(payload.Items) == 0 || len(payload.Items) > 100 {
		writeJSON(w, 400, map[string]any{"error": "batch must contain 1-100 items"})
		return
	}
	created := 0
	for _, item := range payload.Items {
		if !valid(item) {
			writeJSON(w, 400, map[string]any{"error": "invalid observation"})
			return
		}
		ok, err := s.Store.Insert(r.Context(), item)
		if err != nil {
			writeJSON(w, 500, map[string]any{"error": "database write failed"})
			return
		}
		if ok {
			created++
		}
	}
	writeJSON(w, 201, map[string]any{"created": created, "total": len(payload.Items)})
}

func (s *Server) list(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit < 1 {
		limit = 50
	}
	if limit > 100 {
		limit = 100
	}
	var cursor *time.Time
	if raw := r.URL.Query().Get("cursor"); raw != "" {
		if parsed, err := time.Parse(time.RFC3339Nano, raw); err == nil {
			cursor = &parsed
		}
	}
	items, err := s.Store.List(r.Context(), r.URL.Query().Get("instrument_id"), limit, cursor)
	if err != nil {
		writeJSON(w, 500, map[string]any{"error": "database read failed"})
		return
	}
	var next any
	if len(items) == limit {
		next = items[len(items)-1].RequestedAt.Format(time.RFC3339Nano)
	}
	writeJSON(w, 200, map[string]any{"items": items, "next_cursor": next})
}

func valid(item repository.Observation) bool {
	return item.InstrumentID != "" && (item.Kind == "crypto" || item.Kind == "fiat") && item.Base != "" && item.Quote != "" && item.Price != "" && item.Source != "" && !item.SourceTimestamp.IsZero() && !item.RequestedAt.IsZero() && item.RequestID != ""
}

func (s *Server) authorize(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ") != s.Token {
			writeJSON(w, 401, map[string]any{"error": "unauthorized"})
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (s *Server) logging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		started := time.Now()
		next.ServeHTTP(w, r)
		log.Printf(`{"service":"history","route":%q,"latency_ms":%d}`, r.URL.Path, time.Since(started).Milliseconds())
	})
}

func decode(r *http.Request, target any) error {
	r.Body = http.MaxBytesReader(nil, r.Body, 1<<20)
	return json.NewDecoder(r.Body).Decode(target)
}
func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}
