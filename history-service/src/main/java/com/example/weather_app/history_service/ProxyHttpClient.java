package com.example.weather_app.history_service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

@Component
@ConditionalOnProperty(name = "weather.ingestion.mode", havingValue = "pull", matchIfMissing = true)
public class ProxyHttpClient implements ProxyClient {

    private static final Logger log = LoggerFactory.getLogger(ProxyHttpClient.class);

    @Value("${proxy.service.url}")
    private String proxyServiceUrl;

    private final RestClient restClient = RestClient.create();

    @Override
    public WeatherReadingDto fetch(String city, String country) {
        log.info("Requesting weather for {}, {} from proxy-service", city, country);
        try {
            return restClient.get()
                    .uri(proxyServiceUrl + "/proxy/v1/weather?city={city}&country={country}", city, country)
                    .retrieve()
                    .body(WeatherReadingDto.class);
        } catch (Exception e) {
            log.error("Failed to fetch weather for {}, {} from proxy-service: {}", city, country, e.getMessage());
            throw e;
        }
    }
}
