package com.example.weather_app.history_service;

import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

@Configuration
public class WebConfig implements WebMvcConfigurer {

    @Override
    public void addCorsMappings(CorsRegistry registry) {
        registry.addMapping("/api/v1/weather/**")
                .allowedOrigins("http://localhost:5500", "http://127.0.0.1:5500", "http://192.168.0.52:5500", "http://192.168.0.52")
                .allowedMethods("GET");
        registry.addMapping("/api/v1/cities")
                .allowedOrigins("http://localhost:5500", "http://127.0.0.1:5500", "http://192.168.0.52:5500", "http://192.168.0.52")
                .allowedMethods("GET");
        registry.addMapping("/api/v1/preferences")
                .allowedOrigins("http://localhost:5500", "http://127.0.0.1:5500", "http://192.168.0.52:5500", "http://192.168.0.52")
                .allowedMethods("GET", "PUT");
    }
}
