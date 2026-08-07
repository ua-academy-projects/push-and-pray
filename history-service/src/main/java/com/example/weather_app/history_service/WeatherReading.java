package com.example.weather_app.history_service;

import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

import java.time.LocalDateTime;

@Entity
@Table(name = "weather_reading", uniqueConstraints =
        @UniqueConstraint(columnNames = {"city", "country", "observed_at"}))
public class WeatherReading {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private String city;
    private String country;
    private LocalDateTime observedAt;
    private LocalDateTime fetchedAt;
    private double temperatureC;
    private int humidity;
    private String condition;
    private String source;
    private Double pressure;
    private Float windSpeed;

    protected WeatherReading() {}

    public WeatherReading(String city, String country, LocalDateTime observedAt, LocalDateTime fetchedAt,
                           double temperatureC, int humidity, String condition, String source,
                           Double pressure, Float windSpeed) {
        this.city = city;
        this.country = country;
        this.observedAt = observedAt;
        this.fetchedAt = fetchedAt;
        this.temperatureC = temperatureC;
        this.humidity = humidity;
        this.condition = condition;
        this.source = source;
        this.pressure = pressure;
        this.windSpeed = windSpeed;
    }

    public Long getId() { return id; }
    public String getCity() { return city; }
    public String getCountry() { return country; }
    public LocalDateTime getObservedAt() { return observedAt; }
    public LocalDateTime getFetchedAt() { return fetchedAt; }
    public double getTemperatureC() { return temperatureC; }
    public int getHumidity() { return humidity; }
    public String getCondition() { return condition; }
    public String getSource() { return source; }
    public Double getPressure() { return pressure; }
    public Float getWindSpeed() { return windSpeed; }
}
