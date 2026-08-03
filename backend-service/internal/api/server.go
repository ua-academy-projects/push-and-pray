package api

import (
	"encoding/json"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"rateboard/backend-service/internal/repository"
)

type Instrument struct {
	InstrumentID string `json:"instrument_id"`
	Kind         string `json:"kind"`
	Base         string `json:"base"`
	Quote        string `json:"quote"`
	Name         string `json:"name"`
}

var catalog = []Instrument{
	{"crypto:bitcoin:usd", "crypto", "BTC", "USD", "Bitcoin"},
	{"crypto:ethereum:usd", "crypto", "ETH", "USD", "Ethereum"},
	{"crypto:tether:usd", "crypto", "USDT", "USD", "Tether"},
	{"crypto:binancecoin:usd", "crypto", "BNB", "USD", "BNB"},
	{"crypto:solana:usd", "crypto", "SOL", "USD", "Solana"},
	{"crypto:usd-coin:usd", "crypto", "USDC", "USD", "USDC"},
	{"crypto:ripple:usd", "crypto", "XRP", "USD", "XRP"},
	{"crypto:dogecoin:usd", "crypto", "DOGE", "USD", "Dogecoin"},
	{"crypto:cardano:usd", "crypto", "ADA", "USD", "Cardano"},
	{"crypto:tron:usd", "crypto", "TRX", "USD", "TRON"},
	{"fiat:USD:UAH", "fiat", "USD", "UAH", "USD/UAH"},
	{"fiat:EUR:UAH", "fiat", "EUR", "UAH", "EUR/UAH"},
	{"fiat:GBP:UAH", "fiat", "GBP", "UAH", "GBP/UAH"},
	{"fiat:PLN:UAH", "fiat", "PLN", "UAH", "PLN/UAH"},
	{"fiat:CHF:UAH", "fiat", "CHF", "UAH", "CHF/UAH"},
	{"fiat:CAD:UAH", "fiat", "CAD", "UAH", "CAD/UAH"},
	{"fiat:AUD:UAH", "fiat", "AUD", "UAH", "AUD/UAH"},
	{"fiat:JPY:UAH", "fiat", "JPY", "UAH", "JPY/UAH"},
	{"fiat:CNY:UAH", "fiat", "CNY", "UAH", "CNY/UAH"},
	{"fiat:CZK:UAH", "fiat", "CZK", "UAH", "CZK/UAH"},
}

func CatalogIDs() []string {
	ids := make([]string, 0, len(catalog))
	for _, item := range catalog {
		ids = append(ids, item.InstrumentID)
	}
	return ids
}

type Server struct {
	Store   *repository.Store
	MQReady func() bool
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health/live", s.live)
	mux.HandleFunc("GET /health/ready", s.ready)
	mux.HandleFunc("GET /api/v1/instruments", s.instruments)
	mux.HandleFunc("GET /api/v1/overview", s.overview)
	mux.HandleFunc("GET /api/v1/rates/current", s.current)
	mux.HandleFunc("GET /api/v1/rates/stored-current", s.current)
	mux.HandleFunc("GET /api/v1/rates/history", s.series)
	mux.HandleFunc("GET /api/v1/requests/history", s.list)
	mux.HandleFunc("GET /api/v1/market-map", s.marketMap)
	return s.logging(mux)
}

func (s *Server) live(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, 200, map[string]any{"status": "ok", "service": "history-service"})
}

func (s *Server) ready(w http.ResponseWriter, r *http.Request) {
	databaseReady := s.Store.Ping(r.Context()) == nil
	mqReady := s.MQReady == nil || s.MQReady()
	if !databaseReady || !mqReady {
		writeJSON(w, 503, map[string]any{"status": "not_ready", "database": databaseReady, "rabbitmq_consumer": mqReady})
		return
	}
	writeJSON(w, 200, map[string]any{"status": "ready", "database": true, "rabbitmq_consumer": true})
}

func (s *Server) instruments(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, 200, map[string]any{"items": catalog})
}

func splitIDs(raw string, maximum int) ([]string, bool) {
	parts := strings.Split(raw, ",")
	ids := make([]string, 0, len(parts))
	known := map[string]bool{}
	for _, item := range catalog {
		known[item.InstrumentID] = true
	}
	for _, part := range parts {
		id := strings.TrimSpace(part)
		if id != "" {
			if !known[id] {
				return nil, false
			}
			ids = append(ids, id)
		}
	}
	return ids, len(ids) > 0 && len(ids) <= maximum
}

func (s *Server) current(w http.ResponseWriter, r *http.Request) {
	ids, ok := splitIDs(r.URL.Query().Get("instruments"), 10)
	if !ok {
		writeJSON(w, 400, map[string]any{"error": map[string]any{"message": "Provide 1-10 known instruments"}})
		return
	}
	items, err := s.Store.Latest(r.Context(), ids)
	if err != nil {
		writeJSON(w, 500, map[string]any{"error": map[string]any{"message": "database read failed"}})
		return
	}
	writeJSON(w, 200, map[string]any{"items": items, "source": "postgresql"})
}

func (s *Server) overview(w http.ResponseWriter, r *http.Request) {
	items, err := s.Store.Latest(r.Context(), CatalogIDs())
	if err != nil {
		writeJSON(w, 500, map[string]any{"error": map[string]any{"message": "database read failed"}})
		return
	}
	byID := make(map[string]repository.Observation, len(items))
	for _, item := range items {
		byID[item.InstrumentID] = item
	}
	crypto := []repository.Observation{}
	fiat := []repository.Observation{}
	for _, instrument := range catalog {
		item, exists := byID[instrument.InstrumentID]
		if !exists {
			continue
		}
		if item.Name == "" {
			item.Name = instrument.Name
		}
		if instrument.Kind == "crypto" {
			crypto = append(crypto, item)
		} else {
			fiat = append(fiat, item)
		}
	}
	if len(crypto) == 0 {
		writeJSON(w, 503, map[string]any{"error": map[string]any{"message": "PostgreSQL does not contain current crypto observations yet"}})
		return
	}
	writeJSON(w, 200, map[string]any{"primary": crypto[0], "crypto": crypto, "fiat": fiat})
}

func (s *Server) series(w http.ResponseWriter, r *http.Request) {
	steps := map[string]string{"5m": "5 minutes", "30m": "30 minutes", "1h": "1 hour", "4h": "4 hours", "1d": "1 day"}
	step, stepOK := steps[r.URL.Query().Get("step")]
	from, fromErr := time.Parse(time.RFC3339, r.URL.Query().Get("from"))
	to, toErr := time.Parse(time.RFC3339, r.URL.Query().Get("to"))
	ids, idsOK := splitIDs(r.URL.Query().Get("instruments"), 5)
	mode := r.URL.Query().Get("mode")
	if mode == "" {
		mode = "price"
	}
	if !stepOK || fromErr != nil || toErr != nil || !idsOK || from.After(to) ||
		to.Sub(from) > 366*24*time.Hour || (mode != "price" && mode != "percent") {
		writeJSON(w, 400, map[string]any{"error": map[string]any{"message": "invalid history query"}})
		return
	}
	series, err := s.Store.Series(r.Context(), ids, from, to, step)
	if err != nil {
		writeJSON(w, 500, map[string]any{"error": map[string]any{"message": "database read failed"}})
		return
	}
	writeJSON(w, 200, map[string]any{"mode": mode, "series": series})
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
		writeJSON(w, 500, map[string]any{"error": map[string]any{"message": "database read failed"}})
		return
	}
	var next any
	if len(items) == limit {
		next = items[len(items)-1].RequestedAt.Format(time.RFC3339Nano)
	}
	writeJSON(w, 200, map[string]any{"items": items, "next_cursor": next})
}

func (s *Server) marketMap(w http.ResponseWriter, r *http.Request) {
	period := r.URL.Query().Get("period")
	durations := map[string]time.Duration{
		"1h": time.Hour, "4h": 4 * time.Hour, "1d": 24 * time.Hour,
		"7d": 7 * 24 * time.Hour, "30d": 30 * 24 * time.Hour, "1y": 365 * 24 * time.Hour,
	}
	duration, ok := durations[period]
	if !ok {
		writeJSON(w, 400, map[string]any{"error": map[string]any{"message": "unsupported market-map period"}})
		return
	}
	items, err := s.Store.MarketMap(r.Context(), period, time.Now().UTC().Add(-duration))
	if err != nil {
		writeJSON(w, 500, map[string]any{"error": map[string]any{"message": "database read failed"}})
		return
	}
	writeJSON(w, 200, map[string]any{"period": period, "items": items})
}

func (s *Server) logging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		started := time.Now()
		next.ServeHTTP(w, r)
		log.Printf(`{"service":"history-service","route":%q,"latency_ms":%d}`, r.URL.Path, time.Since(started).Milliseconds())
	})
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}
