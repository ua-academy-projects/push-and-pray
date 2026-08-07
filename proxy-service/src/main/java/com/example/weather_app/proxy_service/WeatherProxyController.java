package com.example.weather_app.proxy_service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/proxy/v1")
public class WeatherProxyController {

    private static final Logger log = LoggerFactory.getLogger(WeatherProxyController.class);

    private final WeatherApiClient client;
    private final WeatherReadingMapper mapper;

    public WeatherProxyController(WeatherApiClient client, WeatherReadingMapper mapper) {
        this.client = client;
        this.mapper = mapper;
    }

    @GetMapping("/weather")
    public ResponseEntity<WeatherReadingDto> weather(@RequestParam String city, @RequestParam String country) {
        try {
            ApiWeatherResponse response = client.fetchCurrent(city, country);
            return ResponseEntity.ok(mapper.map(response, city, country));
        } catch (Exception e) {
            log.error("Failed to serve weather for {}, {}: {}", city, country, e.getMessage());
            return ResponseEntity.status(HttpStatus.BAD_GATEWAY).build();
        }
    }
}
