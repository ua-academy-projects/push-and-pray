package provider

import (
	"context"
	"crypto/sha256"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"oil-price-tracker/fetcher/internal/model"
)

const oilPriceAPIBaseURL = "https://api.oilpriceapi.com/v1/prices/latest"

type Provider interface {
	Fetch(context.Context, []model.Series, time.Time) ([]model.Observation, error)
}

type OilPriceAPI struct {
	APIKey string
	Client *http.Client
}

type oilPricePoint struct {
	Price      json.Number    `json:"price"`
	Code       string         `json:"code"`
	Currency   string         `json:"currency"`
	Unit       string         `json:"unit"`
	CreatedAt  string         `json:"created_at"`
	ObservedAt string         `json:"observed_at"`
	UpdatedAt  string         `json:"updated_at"`
	Source     string         `json:"source"`
	DataStatus string         `json:"data_status"`
	Freshness  map[string]any `json:"freshness"`
	Metadata   map[string]any `json:"metadata"`
}

type priceEnvelope struct {
	Prices   []oilPricePoint `json:"prices"`
	Metadata struct {
		Timestamp string `json:"timestamp"`
	} `json:"metadata"`
}

type oilPriceResponse struct {
	Status string          `json:"status"`
	Data   json.RawMessage `json:"data"`
}

func (provider OilPriceAPI) Fetch(
	ctx context.Context,
	series []model.Series,
	slot time.Time,
) ([]model.Observation, error) {
	if len(series) == 0 {
		return nil, fmt.Errorf("no price series configured")
	}

	codes := make([]string, 0, len(series))
	for _, item := range series {
		codes = append(codes, item.SeriesID)
	}
	query := url.Values{"by_code": []string{strings.Join(codes, ",")}}
	endpoint := oilPriceAPIBaseURL + "?" + query.Encode()

	var parsed oilPriceResponse
	err := Retry(ctx, 4, time.Second, func() error {
		request, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
		if err != nil {
			return err
		}
		request.Header.Set("Accept", "application/json")
		request.Header.Set("Authorization", "Token "+provider.APIKey)

		response, err := provider.Client.Do(request)
		if err != nil {
			return err
		}
		defer response.Body.Close()
		if response.StatusCode < 200 || response.StatusCode >= 300 {
			body, _ := io.ReadAll(io.LimitReader(response.Body, 2048))
			return fmt.Errorf(
				"OilPriceAPI returned %s: %s",
				response.Status,
				strings.TrimSpace(string(body)),
			)
		}
		decoder := json.NewDecoder(response.Body)
		decoder.UseNumber()
		if err := decoder.Decode(&parsed); err != nil {
			return fmt.Errorf("decode OilPriceAPI response: %w", err)
		}
		if parsed.Status != "" && parsed.Status != "success" {
			return fmt.Errorf("OilPriceAPI returned status %q", parsed.Status)
		}
		return nil
	})
	if err != nil {
		return nil, err
	}

	return ParseOilPriceResponse(parsed.Data, series, slot, time.Now().UTC(), oilPriceAPIBaseURL)
}

func ParseOilPriceResponse(
	data json.RawMessage,
	series []model.Series,
	slot time.Time,
	fetchedAt time.Time,
	sourceURL string,
) ([]model.Observation, error) {
	var envelope priceEnvelope
	envelopeError := decodeUseNumber(data, &envelope)
	points := envelope.Prices
	if len(points) == 0 {
		arrayError := decodeUseNumber(data, &points)
		if arrayError != nil || len(points) == 0 {
			if envelopeError != nil {
				return nil, fmt.Errorf(
					"decode OilPriceAPI response as envelope (%v) or array (%v)",
					envelopeError,
					arrayError,
				)
			}
			return nil, fmt.Errorf("OilPriceAPI returned no prices")
		}
	}

	byCode := make(map[string]oilPricePoint, len(points))
	for _, point := range points {
		byCode[strings.ToUpper(point.Code)] = point
	}

	observations := make([]model.Observation, 0, len(series))
	for _, item := range series {
		point, ok := byCode[strings.ToUpper(item.SeriesID)]
		if !ok {
			return nil, fmt.Errorf("OilPriceAPI omitted %s from batch response", item.SeriesID)
		}
		observation, err := parseOilPricePoint(
			point,
			item,
			slot,
			fetchedAt,
			sourceURL,
			envelope.Metadata.Timestamp,
		)
		if err != nil {
			return nil, err
		}
		observations = append(observations, observation)
	}
	return observations, nil
}

func parseOilPricePoint(
	point oilPricePoint,
	series model.Series,
	slot time.Time,
	fetchedAt time.Time,
	sourceURL string,
	requestTimestamp string,
) (model.Observation, error) {
	price := point.Price.String()
	numericPrice, err := strconv.ParseFloat(price, 64)
	if err != nil || math.IsNaN(numericPrice) || math.IsInf(numericPrice, 0) || numericPrice <= 0 {
		return model.Observation{}, fmt.Errorf(
			"OilPriceAPI returned invalid price %q for %s",
			price,
			series.SeriesID,
		)
	}

	observedAt, err := firstTimestamp(
		point.ObservedAt,
		point.UpdatedAt,
		point.CreatedAt,
		requestTimestamp,
	)
	if err != nil {
		return model.Observation{}, fmt.Errorf(
			"OilPriceAPI returned no valid timestamp for %s",
			series.SeriesID,
		)
	}
	source := point.Source
	if description, ok := point.Metadata["source_description"].(string); ok && description != "" {
		source = description
	}
	if source == "" {
		source = "OilPriceAPI"
	}
	if len(source) > 80 {
		source = source[:80]
	}

	rawData := map[string]any{}
	encoded, _ := json.Marshal(point)
	_ = decodeUseNumber(encoded, &rawData)

	return model.Observation{
		InstrumentCode: series.Code, InstrumentName: series.Name, Category: series.Category,
		Price: price, Currency: series.Currency, Unit: series.Unit,
		Source: source, SourceSeriesID: series.SeriesID,
		SourcePeriod: observedAt.UTC().Format(time.DateOnly), SourceObservedAt: observedAt.UTC(),
		ScheduledFor: slot.UTC(), FetchedAt: fetchedAt.UTC(),
		SourceURL: sourceURL, RawData: rawData,
	}, nil
}

func firstTimestamp(values ...string) (time.Time, error) {
	for _, value := range values {
		if value == "" {
			continue
		}
		parsed, err := time.Parse(time.RFC3339Nano, value)
		if err == nil {
			return parsed, nil
		}
	}
	return time.Time{}, fmt.Errorf("no valid timestamp")
}

func decodeUseNumber(data []byte, target any) error {
	decoder := json.NewDecoder(strings.NewReader(string(data)))
	decoder.UseNumber()
	return decoder.Decode(target)
}

type Mock struct{}

func (Mock) Fetch(
	_ context.Context,
	series []model.Series,
	slot time.Time,
) ([]model.Observation, error) {
	observations := make([]model.Observation, 0, len(series))
	for _, item := range series {
		digest := sha256.Sum256([]byte(item.SeriesID + ":" + slot.Format(time.RFC3339)))
		fraction := float64(binary.BigEndian.Uint16(digest[:2])) / 65535
		base, scale := 70.0, 20.0
		if item.Category == "gasoline" {
			base, scale = 2.0, 1.0
		}
		price := strconv.FormatFloat(base+fraction*scale, 'f', 3, 64)
		row := map[string]any{
			"created_at": slot.UTC().Format(time.RFC3339),
			"price":      price,
			"code":       item.SeriesID,
		}
		observations = append(observations, model.Observation{
			InstrumentCode: item.Code, InstrumentName: item.Name, Category: item.Category,
			Price: price, Currency: item.Currency, Unit: item.Unit,
			Source: "Deterministic mock provider", SourceSeriesID: item.SeriesID,
			SourcePeriod: slot.UTC().Format(time.DateOnly), SourceObservedAt: slot.UTC(),
			ScheduledFor: slot.UTC(), FetchedAt: time.Now().UTC(),
			SourceURL: "mock://offline-demo", RawData: row,
		})
	}
	return observations, nil
}

func Retry(
	ctx context.Context,
	attempts int,
	initialDelay time.Duration,
	operation func() error,
) error {
	var err error
	for attempt := 0; attempt < attempts; attempt++ {
		if err = operation(); err == nil {
			return nil
		}
		if attempt == attempts-1 {
			break
		}
		timer := time.NewTimer(initialDelay * time.Duration(1<<attempt))
		select {
		case <-ctx.Done():
			timer.Stop()
			return ctx.Err()
		case <-timer.C:
		}
	}
	return err
}
