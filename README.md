# Weather App

Weather App is a microservice-based application that automatically
collects weather data for **Nadvirna**, stores it in PostgreSQL, and
displays both the latest weather and a temperature history chart.

## Features

-   Automatic weather collection every **30 minutes**
-   Fixed location: **Nadvirna, Ukraine**
-   Weather data from **Open-Meteo API**
-   History stored in **PostgreSQL**
-   Temperature history chart built from database records
-   Browser refreshes data every **60 seconds**
-   Opening or refreshing the page **does not call the external API**
-   Protection against duplicate measurements
-   One-click history cleanup with immediate collection of a new
    measurement

## Architecture

``` text
                 +----------------+
                 |  Open-Meteo API|
                 +--------+-------+
                          ^
                          |
                  (every 30 minutes)
                          |
+---------+      +--------+--------+      +----------------+      +--------------+
| Browser | ---> | Backend Service | ---> | History Service| ---> | PostgreSQL   |
+---------+      +--------+--------+      +----------------+      +--------------+
       ^                   |
       |                   |
       +--------- UI Service+
```

When the page is opened:

``` text
Browser
   |
   v
UI Service
   |
   v
Backend
   |
   v
History Service
   |
   v
PostgreSQL
```

The frontend **never calls Open-Meteo directly**.

## Project structure

``` text
weather-app/
├── docker-compose.yml
├── README.md
├── ui-service/
├── backend-service/
└── history-service/
```

## Requirements

-   Docker
-   Docker Compose

``` bash
docker --version
docker compose version
```

## Run

``` bash
docker compose up -d --build
```

Check services:

``` bash
docker compose ps
```

Open:

``` text
http://localhost:5000
```

or (Ubuntu VM)

``` bash
hostname -I
```

Example:

``` text
http://192.168.69.141:5000
```

## Automatic weather collection

Configured in:

``` text
backend-service/app.py
```

``` python
COLLECTION_INTERVAL_MINUTES = 30
MINIMUM_INTERVAL_MINUTES = 25
```

## Automatic page refresh

Configured in:

``` text
ui-service/static/script.js
```

``` javascript
const AUTO_REFRESH_INTERVAL_MS = 60000;
```

This refresh only reads data from PostgreSQL.

## Services

-   UI -- port 5000
-   Backend -- port 5001
-   History -- port 5002
-   PostgreSQL -- port 5432

## Logs

``` bash
docker compose logs -f
docker compose logs -f backend
```

## Stop

``` bash
docker compose down
```

Remove database too:

``` bash
docker compose down -v
```

## Useful commands

``` bash
docker compose up -d --build
docker compose ps
docker compose logs -f
docker compose restart
docker compose down
docker compose down -v
```

## Note

Automatic weather collection works only while the Docker containers are
running.

If the project runs inside VMware Fusion, the Mac, virtual machine and
Docker containers must remain running.

For 24/7 collection, deploy the project to a server such as AWS EC2,
Azure VM, Google Compute Engine or another VPS.
