package com.example.weather_app.history_service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.Duration;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

@RestController
@RequestMapping("/api/v1")
public class WeatherQueryController {

    private static final Logger log = LoggerFactory.getLogger(WeatherQueryController.class);

    private final WeatherReadingRepository repository;
    private final CityTrackingService cityTrackingService;
    private final ProxyClient proxyClient;
    private final WeatherIngestionService ingestionService;
    private final long staleAfterMs;

    public WeatherQueryController(WeatherReadingRepository repository, CityTrackingService cityTrackingService,
                                   ProxyClient proxyClient, WeatherIngestionService ingestionService,
                                   @Value("${history.poll-interval-ms}") long staleAfterMs) {
        this.repository = repository;
        this.cityTrackingService = cityTrackingService;
        this.proxyClient = proxyClient;
        this.ingestionService = ingestionService;
        this.staleAfterMs = staleAfterMs;
    }

    @GetMapping("/weather/current")
    public ResponseEntity<WeatherReading> current(@RequestParam String city, @RequestParam String country,
                                                   @RequestParam(defaultValue = "false") boolean force) {
        city = TextNormalizer.normalizeName(city);
        country = TextNormalizer.normalizeName(country);
        log.info("Current weather requested for {}, {} (force={})", city, country, force);
        cityTrackingService.track(city, country);

        Optional<WeatherReading> existing = repository.findTopByCityAndCountryOrderByObservedAtDesc(city, country);
        boolean isStale = existing.isPresent()
            && existing.get().getFetchedAt().isBefore(LocalDateTime.now().minus(Duration.ofMillis(staleAfterMs)));

        if (existing.isPresent() && !(force && isStale)) {
            return ResponseEntity.ok(existing.get());
        }

        try {
            WeatherReadingDto fetched = proxyClient.fetch(city, country);
            List<WeatherReading> ingested = ingestionService.ingest(List.of(fetched));
            return ResponseEntity.ok(ingested.get(0));
        } catch (Exception e) {
            log.error("On-demand fetch failed for {}, {}: {}", city, country, e.getMessage());
            if (existing.isPresent()) {
                return ResponseEntity.ok(existing.get());
            }
            return ResponseEntity.status(HttpStatus.BAD_GATEWAY).build();
        }
    }

    @GetMapping("/weather/history")
    public List<WeatherReading> history(@RequestParam String city, @RequestParam String country,
                                         @RequestParam(required = false) LocalDateTime from,
                                         @RequestParam(required = false) LocalDateTime to) {
        city = TextNormalizer.normalizeName(city);
        country = TextNormalizer.normalizeName(country);
        log.info("Weather history requested for {}, {} from {} to {}", city, country, from, to);
        if (from == null || to == null) {
            return repository.findByCityAndCountryOrderByObservedAtDesc(city, country);
        }
        return repository.findByCityAndCountryAndFetchedAtBetweenOrderByObservedAtDesc(city, country, from, to);
    }

    @GetMapping("/cities")
    public List<TrackedCity> cities() {
        return cityTrackingService.listTracked();
    }
}
