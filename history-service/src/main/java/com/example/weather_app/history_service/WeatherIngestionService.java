package com.example.weather_app.history_service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

@Service
public class WeatherIngestionService {

    private static final Logger log = LoggerFactory.getLogger(WeatherIngestionService.class);

    private final WeatherReadingRepository repository;

    public WeatherIngestionService(WeatherReadingRepository repository) {
        this.repository = repository;
    }

    public List<WeatherReading> ingest(List<WeatherReadingDto> readings) {
        List<WeatherReading> result = new ArrayList<>();

        for (WeatherReadingDto dto : readings) {
            Optional<WeatherReading> existing =
                    repository.findByCityAndCountryAndObservedAt(dto.city(), dto.country(), dto.observedAt());
            if (existing.isPresent()) {
                log.info("Duplicate reading skipped for {}, {} observed at {}",
                        dto.city(), dto.country(), dto.observedAt());
                result.add(existing.get());
                continue;
            }

            WeatherReading reading = new WeatherReading(
                    dto.city(),
                    dto.country(),
                    dto.observedAt(),
                    dto.fetchedAt() != null ? dto.fetchedAt() : LocalDateTime.now(),
                    dto.temperatureC(),
                    dto.humidity(),
                    dto.condition(),
                    dto.source(),
                    dto.pressure(),
                    dto.windSpeed()
            );
            result.add(repository.save(reading));
            log.info("Ingested reading for {}, {} observed at {}", dto.city(), dto.country(), dto.observedAt());
        }

        return result;
    }
}
