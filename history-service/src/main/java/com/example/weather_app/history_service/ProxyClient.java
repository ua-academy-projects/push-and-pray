package com.example.weather_app.history_service;

public interface ProxyClient {
    WeatherReadingDto fetch(String city, String country);
}
