package model

import "time"

type Series struct {
	Code     string
	Name     string
	Category string
	SeriesID string
	Currency string
	Unit     string
}

var TrackedSeries = []Series{
	{
		Code: "WTI_USD_BBL", Name: "WTI Crude Oil", Category: "crude_oil",
		SeriesID: "WTI_USD", Currency: "USD", Unit: "USD per barrel",
	},
	{
		Code: "BRENT_USD_BBL", Name: "Brent Crude Oil", Category: "crude_oil",
		SeriesID: "BRENT_CRUDE_USD", Currency: "USD", Unit: "USD per barrel",
	},
	{
		Code: "RBOB_GASOLINE_USD_GAL", Name: "RBOB Gasoline", Category: "gasoline",
		SeriesID: "GASOLINE_USD", Currency: "USD", Unit: "USD per gallon",
	},
}

type Observation struct {
	InstrumentCode   string         `json:"instrument_code"`
	InstrumentName   string         `json:"instrument_name"`
	Category         string         `json:"category"`
	Price            string         `json:"price"`
	Currency         string         `json:"currency"`
	Unit             string         `json:"unit"`
	Source           string         `json:"source"`
	SourceSeriesID   string         `json:"source_series_id"`
	SourcePeriod     string         `json:"source_period"`
	SourceObservedAt time.Time      `json:"source_observed_at"`
	ScheduledFor     time.Time      `json:"scheduled_for"`
	FetchedAt        time.Time      `json:"fetched_at"`
	SourceURL        string         `json:"source_url"`
	RawData          map[string]any `json:"raw_data"`
}

type FetchResult struct {
	ScheduledFor time.Time `json:"scheduled_for"`
	FetchedAt    time.Time `json:"fetched_at"`
	Observations int       `json:"observations"`
	Published    int       `json:"published"`
}
