package repository

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type Observation struct {
	ID               string     `json:"id,omitempty"`
	InstrumentID     string     `json:"instrument_id"`
	Kind             string     `json:"kind"`
	Base             string     `json:"base"`
	Quote            string     `json:"quote"`
	Name             string     `json:"name"`
	Price            string     `json:"price"`
	Change1HPercent  *string    `json:"change_1h_percent"`
	Change24HPercent *string    `json:"change_24h_percent"`
	MarketCap        *string    `json:"market_cap"`
	Rank             *int       `json:"rank"`
	Source           string     `json:"source"`
	SourceTimestamp  time.Time  `json:"source_timestamp"`
	RequestedAt      time.Time  `json:"requested_at"`
	Status           string     `json:"status,omitempty"`
	RequestID        string     `json:"request_id"`
	CreatedAt        *time.Time `json:"created_at,omitempty"`
}

type Store struct{ Pool *pgxpool.Pool }

type SeriesPoint struct {
	Timestamp time.Time `json:"timestamp"`
	Value     string    `json:"value"`
}

type Series struct {
	InstrumentID string        `json:"instrument_id"`
	Source       string        `json:"source"`
	Points       []SeriesPoint `json:"points"`
}

type MarketTile struct {
	InstrumentID    string    `json:"instrument_id"`
	Name            string    `json:"name"`
	Symbol          string    `json:"symbol"`
	MarketCap       string    `json:"market_cap"`
	ChangePercent   string    `json:"change_percent"`
	Period          string    `json:"period"`
	Source          string    `json:"source"`
	SourceTimestamp time.Time `json:"source_timestamp"`
}

func Valid(item Observation) bool {
	return item.InstrumentID != "" && (item.Kind == "crypto" || item.Kind == "fiat") &&
		item.Base != "" && item.Quote != "" && item.Price != "" && item.Source != "" &&
		!item.SourceTimestamp.IsZero() && !item.RequestedAt.IsZero() && item.RequestID != ""
}

func New(ctx context.Context, databaseURL string) (*Store, error) {
	pool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		return nil, err
	}
	return &Store{Pool: pool}, nil
}

func (s *Store) Ping(ctx context.Context) error { return s.Pool.Ping(ctx) }
func (s *Store) Close()                         { s.Pool.Close() }

func (s *Store) Insert(ctx context.Context, item Observation) (bool, error) {
	result, err := s.Pool.Exec(ctx, `
		INSERT INTO observations
		(instrument_id, kind, base_code, quote_code, instrument_name, price,
		 change_1h_percent, change_24h_percent, market_cap, rank, source,
		 source_timestamp, requested_at, status, request_id)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,'success',$14)
		ON CONFLICT (source, instrument_id, source_timestamp, requested_at) DO NOTHING`,
		item.InstrumentID, item.Kind, item.Base, item.Quote, item.Name, item.Price,
		item.Change1HPercent, item.Change24HPercent, item.MarketCap, item.Rank,
		item.Source, item.SourceTimestamp, item.RequestedAt, item.RequestID)
	return result.RowsAffected() == 1, err
}

const observationColumns = `
	id::text, instrument_id, kind, base_code, quote_code, instrument_name, price::text,
	change_1h_percent::text, change_24h_percent::text, market_cap::text, rank, source,
	source_timestamp, requested_at, status, request_id::text, created_at`

func scanObservation(row interface{ Scan(...any) error }) (Observation, error) {
	var item Observation
	err := row.Scan(
		&item.ID, &item.InstrumentID, &item.Kind, &item.Base, &item.Quote, &item.Name,
		&item.Price, &item.Change1HPercent, &item.Change24HPercent, &item.MarketCap,
		&item.Rank, &item.Source, &item.SourceTimestamp, &item.RequestedAt,
		&item.Status, &item.RequestID, &item.CreatedAt,
	)
	return item, err
}

func (s *Store) List(ctx context.Context, instrumentID string, limit int, cursor *time.Time) ([]Observation, error) {
	rows, err := s.Pool.Query(ctx, `SELECT `+observationColumns+`
		FROM observations
		WHERE ($1 = '' OR instrument_id = $1) AND ($2::timestamptz IS NULL OR requested_at < $2)
		ORDER BY requested_at DESC LIMIT $3`, instrumentID, cursor, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := make([]Observation, 0, limit)
	for rows.Next() {
		item, scanErr := scanObservation(rows)
		if scanErr != nil {
			return nil, scanErr
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func (s *Store) Latest(ctx context.Context, instrumentIDs []string) ([]Observation, error) {
	rows, err := s.Pool.Query(ctx, `SELECT DISTINCT ON (instrument_id) `+observationColumns+`
		FROM observations
		WHERE cardinality($1::text[]) = 0 OR instrument_id = ANY($1::text[])
		ORDER BY instrument_id, requested_at DESC`, instrumentIDs)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []Observation{}
	for rows.Next() {
		item, scanErr := scanObservation(rows)
		if scanErr != nil {
			return nil, scanErr
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func (s *Store) LatestTimestamps(ctx context.Context) (map[string]time.Time, error) {
	rows, err := s.Pool.Query(ctx, `
		SELECT instrument_id, max(source_timestamp)
		FROM observations WHERE status = 'success' GROUP BY instrument_id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := map[string]time.Time{}
	for rows.Next() {
		var instrumentID string
		var timestamp time.Time
		if err := rows.Scan(&instrumentID, &timestamp); err != nil {
			return nil, err
		}
		result[instrumentID] = timestamp
	}
	return result, rows.Err()
}

func (s *Store) Series(ctx context.Context, instrumentIDs []string, from, to time.Time, interval string) ([]Series, error) {
	result := make([]Series, 0, len(instrumentIDs))
	for _, instrumentID := range instrumentIDs {
		rows, err := s.Pool.Query(ctx, `
			SELECT date_bin($4::interval, requested_at, TIMESTAMPTZ '1970-01-01 00:00:00+00') AS bucket,
			       (array_agg(price::text ORDER BY requested_at DESC))[1],
			       (array_agg(source ORDER BY requested_at DESC))[1]
			FROM observations
			WHERE instrument_id = $1 AND requested_at >= $2 AND requested_at <= $3
			GROUP BY bucket ORDER BY bucket ASC`, instrumentID, from, to, interval)
		if err != nil {
			return nil, err
		}
		series := Series{InstrumentID: instrumentID, Points: []SeriesPoint{}}
		for rows.Next() {
			var point SeriesPoint
			if err := rows.Scan(&point.Timestamp, &point.Value, &series.Source); err != nil {
				rows.Close()
				return nil, err
			}
			series.Points = append(series.Points, point)
		}
		if err := rows.Err(); err != nil {
			rows.Close()
			return nil, err
		}
		rows.Close()
		result = append(result, series)
	}
	return result, nil
}

func (s *Store) MarketMap(ctx context.Context, period string, cutoff time.Time) ([]MarketTile, error) {
	rows, err := s.Pool.Query(ctx, `
		WITH latest AS (
			SELECT DISTINCT ON (instrument_id)
				instrument_id, instrument_name, base_code, market_cap, source, source_timestamp
			FROM observations
			WHERE kind = 'crypto' AND market_cap IS NOT NULL
			ORDER BY instrument_id, requested_at DESC
		)
		SELECT latest.instrument_id, latest.instrument_name, latest.base_code,
		       latest.market_cap::text,
		       CASE WHEN baseline.market_cap IS NULL OR baseline.market_cap = 0 THEN '0'
		            ELSE (((latest.market_cap / baseline.market_cap) - 1) * 100)::text END,
		       latest.source, latest.source_timestamp
		FROM latest
		LEFT JOIN LATERAL (
			SELECT market_cap FROM observations
			WHERE instrument_id = latest.instrument_id AND market_cap IS NOT NULL
			      AND source_timestamp <= $1
			ORDER BY source_timestamp DESC LIMIT 1
		) baseline ON true
		ORDER BY latest.market_cap DESC NULLS LAST LIMIT 10`, cutoff)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []MarketTile{}
	for rows.Next() {
		var item MarketTile
		item.Period = period
		if err := rows.Scan(&item.InstrumentID, &item.Name, &item.Symbol, &item.MarketCap,
			&item.ChangePercent, &item.Source, &item.SourceTimestamp); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}
