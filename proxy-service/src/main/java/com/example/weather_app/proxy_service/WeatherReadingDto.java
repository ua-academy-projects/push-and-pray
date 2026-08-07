package com.example.weather_app.proxy_service;

import java.time.LocalDateTime;

public record WeatherReadingDto(
        String city,
        String country,
        LocalDateTime observedAt,
        LocalDateTime fetchedAt,
        double temperatureC,
        int humidity,
        String condition,
        String source,
        Double pressure,
        Float windSpeed
) {}
