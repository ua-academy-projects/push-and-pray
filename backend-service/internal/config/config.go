package config

import (
	"fmt"
	"os"
)

type Config struct {
	Address                   string
	DatabaseURL               string
	RabbitMQEnabled           bool
	RabbitMQURL               string
	RabbitMQEventsExchange    string
	RabbitMQObservationsQueue string
	RabbitMQObservationRoute  string
	RabbitMQCommandsExchange  string
	RabbitMQCommandsQueue     string
	RabbitMQCommandRoute      string
	StartupBackfillEnabled    bool
	StartupBackfillMaxDays    int
}

func Load() Config {
	host := getenv("BACKEND_SERVICE_HOST", "127.0.0.1")
	port := getenv("BACKEND_SERVICE_PORT", "8081")
	return Config{
		Address:                   host + ":" + port,
		DatabaseURL:               getenv("DATABASE_URL", "postgres://rates:rates@127.0.0.1:5432/rates?sslmode=disable"),
		RabbitMQEnabled:           getenv("RABBITMQ_ENABLED", "true") == "true",
		RabbitMQURL:               getenv("RABBITMQ_URL", "amqp://guest:guest@127.0.0.1:5672/"),
		RabbitMQEventsExchange:    getenv("RABBITMQ_EVENTS_EXCHANGE", "rates.events"),
		RabbitMQObservationsQueue: getenv("RABBITMQ_OBSERVATIONS_QUEUE", "rates.observations"),
		RabbitMQObservationRoute:  getenv("RABBITMQ_OBSERVATION_ROUTING_KEY", "observation.collected"),
		RabbitMQCommandsExchange:  getenv("RABBITMQ_COMMANDS_EXCHANGE", "rates.commands"),
		RabbitMQCommandsQueue:     getenv("RABBITMQ_COMMANDS_QUEUE", "rates.fetch.commands"),
		RabbitMQCommandRoute:      getenv("RABBITMQ_COMMAND_ROUTING_KEY", "backfill.requested"),
		StartupBackfillEnabled:    getenv("STARTUP_BACKFILL_ENABLED", "true") == "true",
		StartupBackfillMaxDays:    getenvInt("STARTUP_BACKFILL_MAX_DAYS", 365),
	}
}

func getenv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func getenvInt(key string, fallback int) int {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	var parsed int
	if _, err := fmt.Sscanf(value, "%d", &parsed); err != nil || parsed < 1 {
		return fallback
	}
	return parsed
}
