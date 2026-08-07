package com.example.weather_app.proxy_service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.core.Message;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class WeatherFetchRequestListener {

    private static final Logger log = LoggerFactory.getLogger(WeatherFetchRequestListener.class);

    private final WeatherApiClient client;
    private final WeatherReadingMapper mapper;
    private final RabbitTemplate rabbitTemplate;

    @Value("${weather.fetch.responses-queue}")
    private String responsesQueue;

    public WeatherFetchRequestListener(WeatherApiClient client, WeatherReadingMapper mapper, RabbitTemplate rabbitTemplate) {
        this.client = client;
        this.mapper = mapper;
        this.rabbitTemplate = rabbitTemplate;
    }

    @RabbitListener(queues = "${weather.fetch.requests-queue}")
    public void handleRequest(WeatherFetchRequest request, Message message) {
        WeatherReadingDto dto;
        try {
            ApiWeatherResponse response = client.fetchCurrent(request.city(), request.country());
            dto = mapper.map(response, request.city(), request.country());
        } catch (Exception e) {
            log.error("Failed to fetch weather for {}, {}: {}", request.city(), request.country(), e.getMessage());
            return;
        }

        String replyTo = message.getMessageProperties().getReplyTo();
        if (replyTo != null) {
            String correlationId = message.getMessageProperties().getCorrelationId();
            rabbitTemplate.convertAndSend(replyTo, dto, m -> {
                m.getMessageProperties().setCorrelationId(correlationId);
                return m;
            });
        } else {
            rabbitTemplate.convertAndSend(responsesQueue, dto);
        }
    }
}
