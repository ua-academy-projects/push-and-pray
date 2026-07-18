# Weather Multi-Service Application

A small multi-service weather application created for DevOps Academy Assignment 1.

## Project goal

The project demonstrates a simple application composed of three independent HTTP services and a PostgreSQL database.

The user can:

- request current weather for a city;
- refresh the displayed weather;
- view previously saved successful requests;
- clear saved history.

## Architecture

The application contains:

1. **UI Service** - serves the web page and communicates only with the Backend Service.
2. **Backend / Proxy Service** - receives UI requests, calls the Open-Meteo public API, and sends successful results to the History Service.
3. **History Service** - owns persistence, saves weather requests, and returns saved history.
4. **PostgreSQL** - stores request timestamps, queries, response data, source, and status.
5. **Open-Meteo API** - provides city geocoding and current weather data.

```text
Browser
   |
   v
UI Service :5000
   |
   v
Backend Service :5001
   | \
   |  +----> Open-Meteo API
   |
   v
History Service :5002
   |
   v
PostgreSQL :5432
```

The browser never calls Open-Meteo or PostgreSQL directly. The UI communicates only with the Backend Service, and only the History Service communicates with the database.

## Repository structure

```text
weather-app/
├── backend-service/
│   ├── app.py
│   └── requirements.txt
├── history-service/
│   ├── .env.example
│   ├── app.py
│   └── requirements.txt
├── ui-service/
│   ├── static/
│   │   ├── script.js
│   │   └── style.css
│   ├── templates/
│   │   └── index.html
│   ├── app.py
│   └── requirements.txt
├── .gitignore
└── README.md
```

## Requirements

- Ubuntu Server
- Python 3.10 or newer
- PostgreSQL
- Internet access for Open-Meteo

## 1. Install system packages

```bash
sudo apt update
sudo apt install -y python3 python3-venv python3-pip postgresql postgresql-contrib
```

Check PostgreSQL:

```bash
sudo systemctl status postgresql --no-pager
```

## 2. Create the PostgreSQL database and user

Open the PostgreSQL console:

```bash
sudo -u postgres psql
```

Run these SQL commands. Replace `StrongPassword123` with your own password:

```sql
CREATE USER weather_user WITH PASSWORD 'StrongPassword123';
CREATE DATABASE weather_history OWNER weather_user;
\q
```

Test the connection:

```bash
psql "postgresql://weather_user:StrongPassword123@127.0.0.1:5432/weather_history"
```

Exit with:

```text
\q
```

## 3. Configure the History Service

```bash
cd history-service
cp .env.example .env
nano .env
```

Set the connection string:

```dotenv
DATABASE_URL=postgresql://weather_user:StrongPassword123@127.0.0.1:5432/weather_history
```

Save in nano with `Ctrl+O`, press `Enter`, and exit with `Ctrl+X`.

## 4. Create virtual environments and install dependencies

Run from the project root:

```bash
cd history-service
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
deactivate

cd ../backend-service
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
deactivate

cd ../ui-service
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
deactivate

cd ..
```

## 5. Run the application

Open three SSH terminal windows connected to the Ubuntu VM.

### Terminal 1 - History Service

```bash
cd ~/weather-app/history-service
source .venv/bin/activate
python app.py
```

The service starts on `127.0.0.1:5002` and creates the `weather_requests` table automatically.

### Terminal 2 - Backend Service

```bash
cd ~/weather-app/backend-service
source .venv/bin/activate
python app.py
```

The service starts on `127.0.0.1:5001`.

### Terminal 3 - UI Service

```bash
cd ~/weather-app/ui-service
source .venv/bin/activate
python app.py
```

The UI starts on `0.0.0.0:5000`.

## 6. Open the application from the MacBook

Find the Ubuntu VM IP address:

```bash
hostname -I
```

Open this address in the MacBook browser:

```text
http://VM_IP_ADDRESS:5000
```

Example:

```text
http://192.168.64.5:5000
```

## 7. Verify the services

Run on the Ubuntu VM:

```bash
curl http://127.0.0.1:5002/health
curl http://127.0.0.1:5001/health
curl http://127.0.0.1:5000/health
```

Expected service status is `ok`.

Test weather through the UI Service route:

```bash
curl "http://127.0.0.1:5000/api/weather?city=Kyiv"
```

Load history:

```bash
curl http://127.0.0.1:5000/api/history
```

Check saved rows directly in PostgreSQL:

```bash
psql "postgresql://weather_user:StrongPassword123@127.0.0.1:5432/weather_history" \
  -c "SELECT id, requested_at, query, source, status FROM weather_requests ORDER BY requested_at DESC;"
```

## API endpoints

### UI Service

- `GET /` - web page
- `GET /health` - UI health check
- `GET /api/weather?city=Kyiv` - proxies a weather request to Backend
- `GET /api/history` - proxies history retrieval to Backend
- `DELETE /api/history` - proxies history deletion to Backend

### Backend Service

- `GET /health` - Backend health check
- `GET /api/weather?city=Kyiv` - gets current weather and asks History Service to save it
- `GET /api/history` - retrieves history through History Service
- `DELETE /api/history` - deletes history through History Service

### History Service

- `GET /health` - checks the service and database connection
- `POST /history` - saves one successful weather request
- `GET /history` - returns the newest 50 requests
- `DELETE /history` - clears all saved requests

## Database schema

The History Service automatically creates this table:

```sql
CREATE TABLE IF NOT EXISTS weather_requests (
    id BIGSERIAL PRIMARY KEY,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    query TEXT NOT NULL,
    response_data JSONB NOT NULL,
    source TEXT,
    status TEXT NOT NULL
);
```

This satisfies the assignment requirements by storing:

- request timestamp;
- requested city;
- response data;
- source metadata;
- request status.

## Service boundaries

- **UI Service** owns presentation and browser interaction.
- **Backend Service** owns external API calls and request orchestration.
- **History Service** owns all database operations.
- **PostgreSQL** is never accessed directly by UI or Backend.

## Stop the application

Press `Ctrl+C` in each of the three terminal windows.