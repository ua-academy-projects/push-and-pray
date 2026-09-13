package config

import (
	"testing"
)

func TestParseHours(t *testing.T) {
	hours, err := ParseHours("18,0,12,6")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	want := []int{0, 6, 12, 18}

	for index := range want {
		if hours[index] != want[index] {
			t.Fatalf(
				"hours[%d] = %d, want %d",
				index,
				hours[index],
				want[index],
			)
		}
	}
}

func TestLoadOilPriceAPIConfiguration(t *testing.T) {
	t.Setenv("DATA_PROVIDER", "oilpriceapi")
	t.Setenv("OILPRICEAPI_KEY", "test-key")
	t.Setenv(
		"DATABASE_URL",
		"postgres://oil_tracker:test@localhost:5432/oil_tracker?sslmode=disable",
	)
	t.Setenv("DATABASE_MODE", "postgres_extensions")

	configuration, err := Load()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if configuration.OilPriceAPIKey != "test-key" {
		t.Fatalf(
			"unexpected API key: %s",
			configuration.OilPriceAPIKey,
		)
	}

	if configuration.DataProvider != "oilpriceapi" {
		t.Fatalf(
			"unexpected provider: %s",
			configuration.DataProvider,
		)
	}

	if configuration.QueueName != "price_observations" {
		t.Fatalf(
			"unexpected PGMQ queue: %s",
			configuration.QueueName,
		)
	}

	if configuration.DatabaseURL == "" {
		t.Fatal("DATABASE_URL should not be empty")
	}
}

func TestLoadManagedConfigurationUsesRabbitMQ(t *testing.T) {
	t.Setenv("DATA_PROVIDER", "mock")
	t.Setenv("DATABASE_MODE", "managed")
	t.Setenv("DATABASE_URL", "")
	t.Setenv("RABBITMQ_URL", "amqp://oil_tracker:test@localhost:5672/oil_tracker")

	configuration, err := Load()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if configuration.DatabaseMode != "managed" || configuration.RabbitMQURL == "" {
		t.Fatalf("unexpected managed configuration: %+v", configuration)
	}
}

func TestParseHoursRejectsInvalidValues(t *testing.T) {
	for _, value := range []string{
		"0,6,12",
		"0,6,12,24",
		"0,6,6,18",
		"a,6,12,18",
	} {
		if _, err := ParseHours(value); err == nil {
			t.Errorf(
				"ParseHours(%q) should fail",
				value,
			)
		}
	}
}
