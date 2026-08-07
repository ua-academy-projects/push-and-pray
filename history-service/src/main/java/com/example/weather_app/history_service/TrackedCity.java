package com.example.weather_app.history_service;

import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;

import java.time.LocalDateTime;

@Entity
@Table(name = "tracked_city", uniqueConstraints =
        @UniqueConstraint(columnNames = {"city", "country"}))
public class TrackedCity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private String city;
    private String country;
    private LocalDateTime requestedAt;

    protected TrackedCity() {}

    public TrackedCity(String city, String country, LocalDateTime requestedAt) {
        this.city = city;
        this.country = country;
        this.requestedAt = requestedAt;
    }

    public Long getId() { return id; }
    public String getCity() { return city; }
    public String getCountry() { return country; }
    public LocalDateTime getRequestedAt() { return requestedAt; }
}
