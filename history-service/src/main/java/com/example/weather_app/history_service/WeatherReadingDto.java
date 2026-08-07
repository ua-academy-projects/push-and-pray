package com.example.weather_app.history_service;

import java.time.LocalDateTime;

public record WeatherReadingDto(
        String city,
        String country,
        LocalDateTime observedAt,
        LocalDateTime fetchedAt,
        Double temperatureC,
        Integer humidity,
        String condition,
        String source,
        Double pressure,
        Float windSpeed
) {}
