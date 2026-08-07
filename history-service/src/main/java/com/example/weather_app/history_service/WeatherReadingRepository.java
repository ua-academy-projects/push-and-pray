package com.example.weather_app.history_service;

import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

public interface WeatherReadingRepository extends JpaRepository<WeatherReading, Long> {

    Optional<WeatherReading> findByCityAndCountryAndObservedAt(String city, String country, LocalDateTime observedAt);

    Optional<WeatherReading> findTopByCityAndCountryOrderByObservedAtDesc(String city, String country);

    List<WeatherReading> findByCityAndCountryAndFetchedAtBetweenOrderByObservedAtDesc(
            String city, String country, LocalDateTime from, LocalDateTime to);

    List<WeatherReading> findByCityAndCountryOrderByObservedAtDesc(String city, String country);
}
