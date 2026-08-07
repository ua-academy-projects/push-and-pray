package com.example.weather_app.redis;

import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.Duration;
import java.util.Set;

@RestController
@RequestMapping("/api/v1")
public class PreferencesController {

    private static final Set<String> ALLOWED_RANGES = Set.of("1d", "7d", "30d");
    private static final Set<String> ALLOWED_METRICS = Set.of("temperatureC", "humidity", "windSpeed", "pressure");
    private static final String DEFAULT_RANGE = "7d";
    private static final String DEFAULT_METRIC = "temperatureC";
    private static final Duration TTL = Duration.ofHours(24);

    private final StringRedisTemplate redisTemplate;

    public PreferencesController(StringRedisTemplate redisTemplate) {
        this.redisTemplate = redisTemplate;
    }

    @GetMapping("/preferences")
    public ResponseEntity<PreferencesDto> get(@RequestHeader(value = "X-Session-Id", required = false) String sessionId) {
        if (sessionId == null || sessionId.isBlank()) {
            return ResponseEntity.badRequest().build();
        }
        return ResponseEntity.ok(current(sessionId));
    }

    @PutMapping("/preferences")
    public ResponseEntity<PreferencesDto> put(@RequestHeader(value = "X-Session-Id", required = false) String sessionId,
                                               @RequestBody PreferencesDto body) {
        if (sessionId == null || sessionId.isBlank()) {
            return ResponseEntity.badRequest().build();
        }
        if (body.range() != null) {
            if (!ALLOWED_RANGES.contains(body.range())) {
                return ResponseEntity.badRequest().build();
            }
            redisTemplate.opsForValue().set(rangeKey(sessionId), body.range(), TTL);
        }
        if (body.metric() != null) {
            if (!ALLOWED_METRICS.contains(body.metric())) {
                return ResponseEntity.badRequest().build();
            }
            redisTemplate.opsForValue().set(metricKey(sessionId), body.metric(), TTL);
        }
        return ResponseEntity.ok(current(sessionId));
    }

    private PreferencesDto current(String sessionId) {
        String range = redisTemplate.opsForValue().get(rangeKey(sessionId));
        String metric = redisTemplate.opsForValue().get(metricKey(sessionId));
        return new PreferencesDto(
                range != null ? range : DEFAULT_RANGE,
                metric != null ? metric : DEFAULT_METRIC);
    }

    private String rangeKey(String sessionId) {
        return "prefs:" + sessionId + ":range";
    }

    private String metricKey(String sessionId) {
        return "prefs:" + sessionId + ":metric";
    }
}
