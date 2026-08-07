package com.example.weather_app.history_service;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface TrackedCityRepository extends JpaRepository<TrackedCity, Long> {

    boolean existsByCityAndCountry(String city, String country);

    List<TrackedCity> findAllByOrderByCity();
}
