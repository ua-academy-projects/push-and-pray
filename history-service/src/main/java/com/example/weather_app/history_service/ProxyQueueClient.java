package com.example.weather_app.history_service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.stereotype.Component;

@Component
@ConditionalOnProperty(name = "weather.ingestion.mode", havingValue = "queue")
public class ProxyQueueClient implements ProxyClient {

    private static final Logger log = LoggerFactory.getLogger(ProxyQueueClient.class);

    private final RabbitTemplate rabbitTemplate;

    @Value("${weather.fetch.requests-queue}")
    private String requestsQueue;

    public ProxyQueueClient(RabbitTemplate rabbitTemplate) {
        this.rabbitTemplate = rabbitTemplate;
    }

    @Override
    public WeatherReadingDto fetch(String city, String country) {
        log.info("Requesting weather for {}, {} via weather.fetch.requests", city, country);
        WeatherReadingDto reading = rabbitTemplate.convertSendAndReceiveAsType(
                requestsQueue, new WeatherFetchRequest(city, country),
                new ParameterizedTypeReference<WeatherReadingDto>() {});
        if (reading == null) {
            throw new IllegalStateException("No response from proxy-service for " + city + ", " + country);
        }
        return reading;
    }
}
