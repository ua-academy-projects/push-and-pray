package com.example.weather_app.history_service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

@Component
public class PreferencesClient {

    private static final Logger log = LoggerFactory.getLogger(PreferencesClient.class);

    @Value("${redis.service.url}")
    private String redisServiceUrl;

    private final RestClient restClient = RestClient.create();

    public PreferencesDto get(String sessionId) {
        log.info("Fetching preferences for session {} from redis-app", sessionId);
        try {
            return restClient.get()
                    .uri(redisServiceUrl + "/api/v1/preferences")
                    .header("X-Session-Id", sessionId)
                    .retrieve()
                    .body(PreferencesDto.class);
        } catch (Exception e) {
            log.error("Failed to fetch preferences for session {}: {}", sessionId, e.getMessage());
            throw e;
        }
    }

    public PreferencesDto put(String sessionId, PreferencesDto preferences) {
        log.info("Storing preferences for session {} in redis-app", sessionId);
        try {
            return restClient.put()
                    .uri(redisServiceUrl + "/api/v1/preferences")
                    .header("X-Session-Id", sessionId)
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(preferences)
                    .retrieve()
                    .body(PreferencesDto.class);
        } catch (Exception e) {
            log.error("Failed to store preferences for session {}: {}", sessionId, e.getMessage());
            throw e;
        }
    }
}
