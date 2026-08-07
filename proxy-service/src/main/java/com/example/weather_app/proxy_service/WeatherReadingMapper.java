package com.example.weather_app.proxy_service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;

@Component
public class WeatherReadingMapper {

    private static final Logger log = LoggerFactory.getLogger(WeatherReadingMapper.class);
    private static final DateTimeFormatter API_TIMESTAMP_FORMAT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm");
    private static final String SOURCE = "weatherapi";

    public WeatherReadingDto map(ApiWeatherResponse response, String city, String country) {
        ApiWeatherResponse.ApiCurrent current = response.current();
        String condition = current.condition() != null ? current.condition().text() : null;

        return new WeatherReadingDto(
                city,
                country,
                parseObservedAt(current.lastUpdated()),
                LocalDateTime.now(),
                current.tempC(),
                Math.round(current.humidity()),
                condition,
                SOURCE,
                current.pressureMb(),
                current.windKph()
        );
    }

    private LocalDateTime parseObservedAt(String lastUpdated) {
        if (lastUpdated == null) {
            return LocalDateTime.now();
        }
        try {
            return LocalDateTime.parse(lastUpdated, API_TIMESTAMP_FORMAT);
        } catch (DateTimeParseException e) {
            log.warn("Could not parse observedAt '{}', falling back to now", lastUpdated);
            return LocalDateTime.now();
        }
    }
}
