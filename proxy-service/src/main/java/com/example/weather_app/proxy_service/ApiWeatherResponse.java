package com.example.weather_app.proxy_service;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

@JsonIgnoreProperties(ignoreUnknown = true)
public record ApiWeatherResponse(ApiLocation location, ApiCurrent current) {

    @JsonIgnoreProperties(ignoreUnknown = true)
    public record ApiLocation(String name, String country) {}

    @JsonIgnoreProperties(ignoreUnknown = true)
    public record ApiCondition(String text) {}

    @JsonIgnoreProperties(ignoreUnknown = true)
    public record ApiCurrent(
            @JsonProperty("last_updated") String lastUpdated,
            @JsonProperty("temp_c") double tempC,
            float humidity,
            @JsonProperty("wind_kph") float windKph,
            @JsonProperty("pressure_mb") double pressureMb,
            ApiCondition condition
    ) {}
}
