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
	t.Setenv("RABBITMQ_URL", "amqp://oil_tracker:test@localhost:5672/oil_tracker")

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
			"unexpected RabbitMQ queue: %s",
			configuration.QueueName,
		)
	}

	if configuration.RabbitMQURL == "" {
		t.Fatal("RABBITMQ_URL should not be empty")
	}
}

func TestLoadRequiresRabbitMQURL(t *testing.T) {
	t.Setenv("DATA_PROVIDER", "mock")
	t.Setenv("RABBITMQ_URL", "")

	if _, err := Load(); err == nil {
		t.Fatal("Load should fail when RABBITMQ_URL is empty")
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
