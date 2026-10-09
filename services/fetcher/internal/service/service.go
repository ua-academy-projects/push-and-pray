package service

import (
	"context"
	"fmt"
	"log/slog"
	"sync"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"

	"oil-price-tracker/fetcher/internal/model"
	"oil-price-tracker/fetcher/internal/provider"
)

var (
	collectionsTotal = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "fetcher_collections_total",
		Help: "Collection runs by result.",
	}, []string{"result"})
	observationsPublished = promauto.NewCounter(prometheus.CounterOpts{
		Name: "fetcher_observations_published_total",
		Help: "Observations published to the queue.",
	})
	lastSuccess = promauto.NewGauge(prometheus.GaugeOpts{
		Name: "fetcher_last_success_timestamp_seconds",
		Help: "Unix time of the last successful collection.",
	})
)

type Publisher interface {
	Publish(context.Context, []model.Observation) error
}

type Service struct {
	provider  provider.Provider
	publisher Publisher
	running   bool
	mu        sync.RWMutex
	last      *model.FetchResult
	lastErr   string
}

func New(priceProvider provider.Provider, publisher Publisher) *Service {
	return &Service{provider: priceProvider, publisher: publisher}
}

func (service *Service) Run(ctx context.Context, slot time.Time) (model.FetchResult, error) {
	service.mu.Lock()
	if service.running {
		service.mu.Unlock()
		return model.FetchResult{}, fmt.Errorf("collection is already running")
	}
	service.running = true
	service.mu.Unlock()
	defer func() {
		service.mu.Lock()
		service.running = false
		service.mu.Unlock()
	}()

	slog.Info("starting collection", "scheduled_for", slot)
	observations, err := service.provider.Fetch(ctx, model.TrackedSeries, slot)
	if err != nil {
		service.recordError(err)
		return model.FetchResult{}, fmt.Errorf("fetch prices: %w", err)
	}

	if err := service.publisher.Publish(ctx, observations); err != nil {
		service.recordError(err)
		return model.FetchResult{}, fmt.Errorf("publish observations: %w", err)
	}
	result := model.FetchResult{
		ScheduledFor: slot.UTC(), FetchedAt: time.Now().UTC(), Observations: len(observations),
		Published: len(observations),
	}
	service.mu.Lock()
	service.last = &result
	service.lastErr = ""
	service.mu.Unlock()
	collectionsTotal.WithLabelValues("success").Inc()
	observationsPublished.Add(float64(result.Published))
	lastSuccess.SetToCurrentTime()
	slog.Info("collection published", "observations", result.Published)
	return result, nil
}

func (service *Service) Status() (bool, *model.FetchResult, string) {
	service.mu.RLock()
	defer service.mu.RUnlock()
	var copied *model.FetchResult
	if service.last != nil {
		value := *service.last
		copied = &value
	}
	return service.running, copied, service.lastErr
}

func (service *Service) recordError(err error) {
	service.mu.Lock()
	service.lastErr = err.Error()
	service.mu.Unlock()
	collectionsTotal.WithLabelValues("error").Inc()
	slog.Error("collection failed", "error", err)
}
