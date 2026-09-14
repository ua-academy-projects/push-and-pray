package config

import (
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	OilPriceAPIKey   string
	DataProvider     string
	DatabaseURL      string
	QueueName        string
	MessagingBackend string
	RabbitMQHost     string
	RabbitMQPort     int
	RabbitMQUser     string
	RabbitMQPassword string
	RabbitMQVHost    string
	CronHours        []int
	Timezone         *time.Location
	FetchOnStartup   bool
	RequestTimeout   time.Duration
	ListenAddress    string
}

func Load() (Config, error) {
	provider := strings.ToLower(env("DATA_PROVIDER", "oilpriceapi"))
	if provider != "oilpriceapi" && provider != "mock" {
		return Config{}, fmt.Errorf("DATA_PROVIDER must be oilpriceapi or mock")
	}

	apiKey := os.Getenv("OILPRICEAPI_KEY")
	if provider == "oilpriceapi" && apiKey == "" {
		return Config{}, fmt.Errorf("OILPRICEAPI_KEY is required when DATA_PROVIDER=oilpriceapi")
	}

	databaseURL := strings.TrimSpace(env(
		"DATABASE_URL",
		"postgres://oil_tracker:change-me@localhost:5432/oil_tracker?sslmode=disable",
	))
	messagingBackend := strings.ToLower(env("MESSAGING_BACKEND", "pgmq"))
	if messagingBackend != "pgmq" && messagingBackend != "rabbitmq" {
		return Config{}, fmt.Errorf("MESSAGING_BACKEND must be pgmq or rabbitmq")
	}
	if messagingBackend == "pgmq" && databaseURL == "" {
		return Config{}, fmt.Errorf("DATABASE_URL must not be empty")
	}

	rabbitMQPort, err := strconv.Atoi(env("RABBITMQ_PORT", "5672"))
	if err != nil || rabbitMQPort < 1 || rabbitMQPort > 65535 {
		return Config{}, fmt.Errorf("RABBITMQ_PORT must be a valid port")
	}
	rabbitMQHost := strings.TrimSpace(os.Getenv("RABBITMQ_HOST"))
	rabbitMQPassword := os.Getenv("RABBITMQ_PASSWORD")
	if messagingBackend == "rabbitmq" && (rabbitMQHost == "" || rabbitMQPassword == "") {
		return Config{}, fmt.Errorf("RABBITMQ_HOST and RABBITMQ_PASSWORD are required")
	}
	queueName := env("PGMQ_QUEUE", "price_observations")
	if messagingBackend == "rabbitmq" {
		queueName = env("RABBITMQ_QUEUE", "price_observations")
	}

	hours, err := ParseHours(env("FETCH_CRON_HOURS", "0,6,12,18"))
	if err != nil {
		return Config{}, err
	}

	location, err := time.LoadLocation(env("FETCH_TIMEZONE", "UTC"))
	if err != nil {
		return Config{}, fmt.Errorf("load FETCH_TIMEZONE: %w", err)
	}

	fetchOnStartup, err := strconv.ParseBool(env("FETCH_ON_STARTUP", "true"))
	if err != nil {
		return Config{}, fmt.Errorf("parse FETCH_ON_STARTUP: %w", err)
	}

	timeoutSeconds, err := strconv.Atoi(env("REQUEST_TIMEOUT_SECONDS", "15"))
	if err != nil || timeoutSeconds < 1 {
		return Config{}, fmt.Errorf("REQUEST_TIMEOUT_SECONDS must be a positive integer")
	}

	return Config{
		OilPriceAPIKey:   apiKey,
		DataProvider:     provider,
		DatabaseURL:      databaseURL,
		QueueName:        queueName,
		MessagingBackend: messagingBackend,
		RabbitMQHost:     rabbitMQHost,
		RabbitMQPort:     rabbitMQPort,
		RabbitMQUser:     env("RABBITMQ_USER", "oil_tracker"),
		RabbitMQPassword: rabbitMQPassword,
		RabbitMQVHost:    env("RABBITMQ_VHOST", "oil_tracker"),
		CronHours:        hours,
		Timezone:         location,
		FetchOnStartup:   fetchOnStartup,
		RequestTimeout:   time.Duration(timeoutSeconds) * time.Second,
		ListenAddress:    env("LISTEN_ADDRESS", ":8002"),
	}, nil
}

func ParseHours(value string) ([]int, error) {
	parts := strings.Split(value, ",")
	if len(parts) != 4 {
		return nil, fmt.Errorf("FETCH_CRON_HOURS must contain exactly four hours")
	}

	seen := make(map[int]bool, 4)
	hours := make([]int, 0, 4)

	for _, part := range parts {
		hour, err := strconv.Atoi(strings.TrimSpace(part))
		if err != nil || hour < 0 || hour > 23 {
			return nil, fmt.Errorf("invalid hour %q in FETCH_CRON_HOURS", part)
		}

		if seen[hour] {
			return nil, fmt.Errorf("FETCH_CRON_HOURS must contain distinct hours")
		}

		seen[hour] = true
		hours = append(hours, hour)
	}

	sort.Ints(hours)
	return hours, nil
}

func env(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok {
		return value
	}

	return fallback
}
