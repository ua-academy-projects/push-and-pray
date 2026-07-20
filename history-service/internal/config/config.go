package config

import "os"

type Config struct {
	Address     string
	DatabaseURL string
	Token       string
}

func Load() Config {
	host := getenv("HISTORY_HOST", "127.0.0.1")
	port := getenv("HISTORY_PORT", "8081")
	return Config{
		Address:     host + ":" + port,
		DatabaseURL: getenv("DATABASE_URL", "postgres://rates:rates@127.0.0.1:5432/rates?sslmode=disable"),
		Token:       getenv("HISTORY_SERVICE_TOKEN", "change-me"),
	}
}

func getenv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
