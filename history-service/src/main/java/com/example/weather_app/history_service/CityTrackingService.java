package com.example.weather_app.history_service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.util.List;

@Service
public class CityTrackingService {

    private static final Logger log = LoggerFactory.getLogger(CityTrackingService.class);

    private final TrackedCityRepository repository;

    public CityTrackingService(TrackedCityRepository repository) {
        this.repository = repository;
    }

    public void track(String city, String country) {
        if (repository.existsByCityAndCountry(city, country)) {
            return;
        }
        repository.save(new TrackedCity(city, country, LocalDateTime.now()));
        log.info("Started tracking {}, {}", city, country);
    }

    public List<TrackedCity> listTracked() {
        return repository.findAllByOrderByCity();
    }
}
