# AirAware Architecture

## 1. System overview

AirAware is a distributed air-quality monitoring application deployed across four Vagrant-managed virtual machines.

The system collects measurements from Open-Meteo, stores them in PostgreSQL, and displays current and historical information in a browser dashboard.

```text
Open-Meteo
    |
    v
API Fetcher Service
    |
    v
Backend Service
    |
    v
PostgreSQL

Frontend Service
    |
    v
Backend Service
```

The Frontend and API Fetcher are independent clients of the Backend. They never communicate directly with each other.

## 2. Component diagram

```text
                            Internet
                               |
                               v
                    Open-Meteo Air Quality API
                               ^
                               |
                               | HTTPS
                               |
                 +-----------------------------+
                 | API Fetcher VM              |
                 | 192.168.50.212:8000         |
                 | FastAPI + APScheduler       |
                 +-------------+---------------+
                               |
                               | HTTP POST
                               | /api/measurements
                               v
+-----------------------------+-----------------------------+
| Backend VM                                                |
| 192.168.50.211:8001                                     |
| FastAPI + SQLAlchemy + Psycopg                           |
+--------------------------+-------------------------------+
                           |
                           | PostgreSQL protocol
                           v
                 +-----------------------------+
                 | Database VM                 |
                 | 192.168.50.213:5432         |
                 | PostgreSQL                  |
                 +-----------------------------+

+-----------------------------+
| Frontend VM                 |
| 192.168.50.210:5000         |
| Flask + HTML/CSS/JavaScript |
+-------------+---------------+
              |
              | HTTP GET
              | /api/cities
              | /api/dashboard
              v
        Backend VM
```

## 3. Service responsibilities

### 3.1 Frontend Service

The Frontend Service:

- serves the browser interface;
- loads the configured city list;
- requests dashboard data from the Backend;
- displays the latest stored measurement;
- displays 12-hour or 24-hour historical trends;
- switches between metrics without contacting the API Fetcher;
- never connects to PostgreSQL.

The Refresh button reloads stored data from the Backend. It does not trigger a new Open-Meteo fetch.

### 3.2 Backend Service

The Backend Service is the central application API and data-access layer.

It:

- accepts measurements from the API Fetcher;
- validates incoming payloads;
- resolves city codes;
- prevents duplicate records;
- stores measurements in PostgreSQL;
- returns active cities;
- returns the latest measurement for a city;
- returns historical measurements for a requested period;
- owns all database access.

### 3.3 API Fetcher Service

The API Fetcher Service:

- retrieves the active city list from the Backend;
- requests current values from Open-Meteo;
- normalises the provider response;
- sends each measurement to the Backend;
- runs automatically every hour;
- supports a manual fetch endpoint;
- never connects directly to PostgreSQL;
- never communicates with the Frontend.

### 3.4 PostgreSQL

PostgreSQL stores two main entities:

- configured cities;
- hourly air-quality measurements.

The database is reachable remotely only from the Backend VM through PostgreSQL authentication rules.

## 4. Network topology

The deployment uses VirtualBox bridged networking through Vagrant `public_network`.

```text
Home LAN: 192.168.50.0/24

Frontend VM: 192.168.50.210
Backend VM:  192.168.50.211
Fetcher VM:  192.168.50.212
Database VM: 192.168.50.213
Gateway:     192.168.50.1
```

Each VM appears as a separate device on the home network.

Another device on the same LAN can access:

```text
Frontend: http://192.168.50.210:5000
Backend:  http://192.168.50.211:8001
Fetcher:  http://192.168.50.212:8000
```

Inter-service communication never uses `localhost`.

`localhost` is used only for service self-checks within the same VM.

## 5. Application flows

### 5.1 Scheduled collection flow

```text
1. APScheduler starts an hourly job.
2. API Fetcher requests the active city list from Backend.
3. API Fetcher requests Open-Meteo data for each city.
4. Measurements are normalised.
5. API Fetcher sends them to Backend.
6. Backend validates the payload.
7. Backend inserts a record into PostgreSQL.
8. PostgreSQL rejects duplicate city/time combinations.
```

### 5.2 Dashboard flow

```text
1. Browser opens the Frontend.
2. Frontend requests cities through its local proxy route.
3. Frontend Service requests /api/cities from Backend.
4. Browser selects a city and period.
5. Frontend Service requests /api/dashboard from Backend.
6. Backend queries PostgreSQL.
7. Backend returns the latest and historical measurements.
8. Frontend renders metric cards and a graph.
```

## 6. Database design

### 6.1 `cities`

Stores stable city configuration:

- ID
- code
- name
- country
- latitude
- longitude
- timezone
- active state
- creation timestamp

### 6.2 `air_quality_measurements`

Stores time-series measurements:

- city ID
- observation timestamp
- fetch timestamp
- European AQI
- US AQI
- PM2.5
- PM10
- nitrogen dioxide
- ozone
- carbon monoxide
- UV index
- source
- source status code

A unique constraint exists on:

```text
(city_id, observed_at)
```

This prevents duplicate records when:

- the Fetcher restarts;
- startup fetch and scheduled fetch overlap;
- the manual fetch endpoint is called repeatedly;
- Open-Meteo still returns the same hourly observation.

## 7. Scheduling design

The Fetcher uses an hourly cron-style schedule rather than a 60-minute interval from process startup.

Recommended behaviour:

```text
Startup fetch: immediately
Scheduled fetch: every hour at HH:05
Manual fetch: independent of the schedule
```

Using a small delay after the hour gives the provider time to publish the latest observation.

## 8. Time handling

- Open-Meteo timestamps are treated as UTC.
- PostgreSQL stores `TIMESTAMPTZ`.
- Backend returns timezone-aware timestamps.
- Frontend displays values in the configured city timezone.
- Graph axis labels and tooltips use local city time.

## 9. Failure behaviour

### Backend unavailable

- Frontend readiness returns `503`.
- API Fetcher readiness returns `503`.
- Scheduled collection fails and logs the error.

### PostgreSQL unavailable

- Backend readiness returns `503`.
- Dashboard and measurement requests fail.
- Frontend cannot load data.

### Open-Meteo unavailable

- Existing stored data remains available through the Frontend.
- Fetcher logs per-city failures.
- The Backend and Frontend continue running.

### Duplicate measurement

- Backend returns the existing record.
- The result indicates that a new record was not created.
- No duplicate database row is inserted.

## 10. Security boundaries

Current controls:

- PostgreSQL accepts the application user only from the Backend VM address.
- The Frontend and Fetcher do not receive database credentials.
- Services run as a dedicated `airaware` system user.
- `.env` files are created inside VMs with restricted permissions.
- Real `.env` files are excluded from Git.

## 11. Design decisions

### Separate Backend and Fetcher

The Fetcher is responsible for ingestion and scheduling. The Backend is responsible for validation and persistence. This makes the system easier to scale and test.

### Frontend does not contact Fetcher

The Frontend reads stored data only. It remains available even when the Fetcher or Open-Meteo is temporarily unavailable.

### Backend owns the database

A single service owns persistence and database credentials, reducing coupling and improving security.

### Structured measurements instead of generic JSON history

Structured columns simplify filtering, indexing, graph generation, validation, and future analytics.

### Bridged networking

Bridged networking makes every VM visible as a separate LAN device and demonstrates real machine-to-machine communication without using host port forwarding.

### systemd services

Application processes run independently of SSH sessions and start automatically with the VMs.
