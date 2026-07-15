# Weather Multi-Service Application

A small multi-service weather application created as part of the DevOps Academy Assignment 1.

## Project goal

The goal of this project is to build a working application composed of three separate services and a relational database.

The application allows a user to:

- request current weather data for a city;
- refresh the current weather data;
- view the history of previous successful requests.

## Architecture

The application consists of:

1. UI Service
2. Backend / Proxy Service
3. History Service
4. PostgreSQL database
5. External public weather API

Expected communication flow:

```text
Browser
   |
   v
UI Service
   |
   v
Backend Service
   | \
   |  \--> Public Weather API
   |
   v
History Service
   |
   v
PostgreSQL
