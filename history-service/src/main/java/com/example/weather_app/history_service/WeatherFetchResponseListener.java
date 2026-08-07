package com.example.weather_app.history_service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

import java.util.List;

@Component
@ConditionalOnProperty(name = "weather.ingestion.mode", havingValue = "queue")
public class WeatherFetchResponseListener {

    private static final Logger log = LoggerFactory.getLogger(WeatherFetchResponseListener.class);

    private final WeatherIngestionService ingestionService;

    public WeatherFetchResponseListener(WeatherIngestionService ingestionService) {
        this.ingestionService = ingestionService;
    }

    @RabbitListener(queues = "${weather.fetch.responses-queue}")
    public void onResponse(WeatherReadingDto dto) {
        try {
            ingestionService.ingest(List.of(dto));
        } catch (Exception e) {
            log.error("Failed to ingest queued reading for {}, {}: {}", dto.city(), dto.country(), e.getMessage());
        }
    }
}
