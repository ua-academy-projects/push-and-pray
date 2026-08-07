package com.example.weather_app.history_service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
@ConditionalOnProperty(name = "weather.ingestion.mode", havingValue = "queue")
public class QueuePollingScheduler {

    private static final Logger log = LoggerFactory.getLogger(QueuePollingScheduler.class);

    private final CityTrackingService cityTrackingService;
    private final RabbitTemplate rabbitTemplate;
    private final String requestsQueue;

    public QueuePollingScheduler(CityTrackingService cityTrackingService, RabbitTemplate rabbitTemplate,
                                  @Value("${weather.fetch.requests-queue}") String requestsQueue) {
        this.cityTrackingService = cityTrackingService;
        this.rabbitTemplate = rabbitTemplate;
        this.requestsQueue = requestsQueue;
    }

    @Scheduled(fixedDelayString = "${history.poll-interval-ms}")
    public void pollTrackedCities() {
        log.info("Starting scheduled poll tick");
        try {
            for (TrackedCity city : cityTrackingService.listTracked()) {
                try {
                    rabbitTemplate.convertAndSend(requestsQueue, new WeatherFetchRequest(city.getCity(), city.getCountry()));
                } catch (Exception e) {
                    log.error("Failed to publish fetch request for {}, {}", city.getCity(), city.getCountry(), e);
                }
            }
        } catch (Throwable t) {
            // A scheduled method must never let anything escape: fixedDelay tasks are
            // silently cancelled forever (with zero log output from the scheduler
            // itself) the first time this happens, which is exactly the bug being
            // chased here.
            log.error("Scheduled poll tick failed unexpectedly", t);
        }
        log.info("Finished scheduled poll tick");
    }
}
