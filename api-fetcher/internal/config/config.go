package config

import "os"

type Config struct {
	Address            string
	DatabaseURL        string
	Token              string
	RabbitMQEnabled    bool
	RabbitMQURL        string
	RabbitMQExchange   string
	RabbitMQQueue      string
	RabbitMQRoutingKey string
}

func Load() Config {
	host := getenv("API_FETCHER_HOST", "127.0.0.1")
	port := getenv("API_FETCHER_PORT", "8081")
	return Config{
		Address:            host + ":" + port,
		DatabaseURL:        getenv("DATABASE_URL", "postgres://rates:rates@127.0.0.1:5432/rates?sslmode=disable"),
		Token:              getenv("API_FETCHER_TOKEN", "change-me"),
		RabbitMQEnabled:    getenv("RABBITMQ_ENABLED", "false") == "true",
		RabbitMQURL:        getenv("RABBITMQ_URL", "amqp://guest:guest@127.0.0.1:5672/"),
		RabbitMQExchange:   getenv("RABBITMQ_EXCHANGE", "rates.events"),
		RabbitMQQueue:      getenv("RABBITMQ_QUEUE", "rates.observations"),
		RabbitMQRoutingKey: getenv("RABBITMQ_ROUTING_KEY", "observation.persist"),
	}
}

func getenv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
