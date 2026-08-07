package com.example.weather_app.proxy_service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;

@Component
public class WeatherApiClient {

    private static final Logger log = LoggerFactory.getLogger(WeatherApiClient.class);

    @Value("${weather.api.url}")
    private String apiUrl;

    @Value("${weather.api.key}")
    private String apiKey;

    private final RestClient restClient = RestClient.create();

    public ApiWeatherResponse fetchCurrent(String city, String country) {
        String query = encode(city) + "," + encode(country);
        log.info("Fetching weather for {}, {}", city, country);
        try {
            return restClient.get()
                    .uri(apiUrl + "/current.json?key=" + apiKey + "&q=" + query + "&aqi=no")
                    .retrieve()
                    .body(ApiWeatherResponse.class);
        } catch (Exception e) {
            log.error("Failed to fetch weather for {}, {}: {}", city, country, e.getMessage());
            throw e;
        }
    }

    private String encode(String value) {
        return URLEncoder.encode(value, StandardCharsets.UTF_8);
    }
}
