package com.example.weather_app.history_service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.List;

@Component
@ConditionalOnProperty(name = "weather.ingestion.mode", havingValue = "pull", matchIfMissing = true)
public class HistoryPollingScheduler {

    private static final Logger log = LoggerFactory.getLogger(HistoryPollingScheduler.class);

    private final CityTrackingService cityTrackingService;
    private final ProxyClient proxyClient;
    private final WeatherIngestionService ingestionService;

    public HistoryPollingScheduler(CityTrackingService cityTrackingService, ProxyClient proxyClient,
                                    WeatherIngestionService ingestionService) {
        this.cityTrackingService = cityTrackingService;
        this.proxyClient = proxyClient;
        this.ingestionService = ingestionService;
    }

    @Scheduled(fixedDelayString = "${history.poll-interval-ms}")
    public void pollTrackedCities() {
        for (TrackedCity city : cityTrackingService.listTracked()) {
            try {
                WeatherReadingDto reading = proxyClient.fetch(city.getCity(), city.getCountry());
                ingestionService.ingest(List.of(reading));
            } catch (Exception e) {
                log.error("Failed to refresh weather for {}, {}", city.getCity(), city.getCountry(), e);
            }
        }
    }
}
