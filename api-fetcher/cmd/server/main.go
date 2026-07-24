package main

import (
	"context"
	"log"
	"net/http"
	"os/signal"
	"syscall"
	"time"

	"rateboard/api-fetcher/internal/api"
	"rateboard/api-fetcher/internal/config"
	queue "rateboard/api-fetcher/internal/messaging"
	"rateboard/api-fetcher/internal/repository"
)

func main() {
	cfg := config.Load()
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	store, err := repository.New(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatal(err)
	}
	defer store.Close()
	if cfg.RabbitMQEnabled {
		consumer := &queue.Consumer{
			URL: cfg.RabbitMQURL, Exchange: cfg.RabbitMQExchange, Queue: cfg.RabbitMQQueue,
			RoutingKey: cfg.RabbitMQRoutingKey, Store: store,
		}
		go consumer.Run(ctx)
	}
	server := &http.Server{Addr: cfg.Address, Handler: (&api.Server{Store: store, Token: cfg.Token}).Handler(), ReadHeaderTimeout: 5 * time.Second}
	go func() {
		log.Printf("api-fetcher listening on %s", cfg.Address)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatal(err)
		}
	}()
	<-ctx.Done()
	shutdown, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = server.Shutdown(shutdown)
}
