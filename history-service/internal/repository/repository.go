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
	Name             string     `json:"name,omitempty"`
	Price            string     `json:"price"`
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
		(instrument_id, kind, base_code, quote_code, price, change_24h_percent, market_cap, rank, source, source_timestamp, requested_at, status, request_id)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,'success',$12)
		ON CONFLICT (source, instrument_id, source_timestamp, requested_at) DO NOTHING`,
		item.InstrumentID, item.Kind, item.Base, item.Quote, item.Price, item.Change24HPercent,
		item.MarketCap, item.Rank, item.Source, item.SourceTimestamp, item.RequestedAt, item.RequestID)
	return result.RowsAffected() == 1, err
}

func (s *Store) List(ctx context.Context, instrumentID string, limit int, cursor *time.Time) ([]Observation, error) {
	rows, err := s.Pool.Query(ctx, `
		SELECT id::text, instrument_id, kind, base_code, quote_code, price::text,
		       change_24h_percent::text, market_cap::text, rank, source, source_timestamp,
		       requested_at, status, request_id::text, created_at
		FROM observations
		WHERE ($1 = '' OR instrument_id = $1) AND ($2::timestamptz IS NULL OR requested_at < $2)
		ORDER BY requested_at DESC LIMIT $3`, instrumentID, cursor, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := make([]Observation, 0, limit)
	for rows.Next() {
		var item Observation
		if err := rows.Scan(&item.ID, &item.InstrumentID, &item.Kind, &item.Base, &item.Quote, &item.Price,
			&item.Change24HPercent, &item.MarketCap, &item.Rank, &item.Source, &item.SourceTimestamp,
			&item.RequestedAt, &item.Status, &item.RequestID, &item.CreatedAt); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func (s *Store) Series(ctx context.Context, instrumentIDs []string, from, to time.Time, interval string) ([]Series, error) {
	result := make([]Series, 0, len(instrumentIDs))
	for _, instrumentID := range instrumentIDs {
		rows, err := s.Pool.Query(ctx, `
			SELECT date_bin($4::interval, requested_at, TIMESTAMPTZ '1970-01-01 00:00:00+00') AS bucket,
			       (array_agg(price::text ORDER BY requested_at DESC))[1] AS price,
			       (array_agg(source ORDER BY requested_at DESC))[1] AS source
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
