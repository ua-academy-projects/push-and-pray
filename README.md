# Weather App

Weather App is a small microservice-based application for retrieving weather information and storing the request history.

The project is divided into separate services and runs with Docker Compose.

## Architecture

The application consists of four services:

- **UI service** — web interface available on port `5000`.
- **Backend service** — processes weather requests on port `5001`.
- **History service** — stores and returns request history on port `5002`.
- **PostgreSQL** — stores history-service data.

Service communication:

```text
User
  |
  v
UI service
  |
  v
Backend service
  |
  v
History service
  |
  v
PostgreSQL
```

Inside the Docker network, services communicate using their Compose service names:

```text
UI -> http://backend:5001
Backend -> http://history:5002
History -> postgres:5432
```

## Project structure

```text
weather-app/
├── docker-compose.yml
├── README.md
├── .gitignore
│
├── ui-service/
│   ├── Dockerfile
│   ├── .dockerignore
│   ├── app.py
│   ├── requirements.txt
│   ├── templates/
│   │   └── index.html
│   └── static/
│       ├── script.js
│       └── style.css
│
├── backend-service/
│   ├── Dockerfile
│   ├── .dockerignore
│   ├── app.py
│   └── requirements.txt
│
└── history-service/
    ├── Dockerfile
    ├── .dockerignore
    ├── .env.example
    ├── app.py
    └── requirements.txt
```

## Requirements

To run the project, install:

- Docker
- Docker Compose

Check that they are available:

```bash
docker --version
docker compose version
```

## Run the project

Open the project directory:

```bash
cd weather-app
```

Build the images and start all containers:

```bash
docker compose up -d --build
```

The `--build` option rebuilds the application images.

The `-d` option starts the containers in the background.

## Check container status

```bash
docker compose ps
```

The following services should be running:

```text
postgres
history
backend
ui
```

## Open the application

When running Docker directly on your computer:

```text
http://localhost:5000
```

When Docker is running inside an Ubuntu virtual machine, find the VM IP:

```bash
hostname -I
```

Then open:

```text
http://VM_IP_ADDRESS:5000
```

Example:

```text
http://192.168.69.141:5000
```

Do not use container addresses such as `172.18.0.x` in a browser outside the Ubuntu virtual machine. Those addresses are available only inside the Docker network.

## View logs

View logs from all services:

```bash
docker compose logs -f
```

View logs from one service:

```bash
docker compose logs -f ui
docker compose logs -f backend
docker compose logs -f history
docker compose logs -f postgres
```

Press `Ctrl+C` to exit log viewing.

## Stop the project

Stop and remove the containers and Docker network:

```bash
docker compose down
```

The PostgreSQL data remains stored in the Docker volume.

To remove the containers together with the PostgreSQL data:

```bash
docker compose down -v
```

## Restart the project

```bash
docker compose restart
```

## Rebuild after code changes

After changing application code, dependencies, or Dockerfiles:

```bash
docker compose up -d --build
```

## Environment variables

Docker Compose passes the following variables to the services:

### UI service

```text
APP_HOST=0.0.0.0
APP_PORT=5000
BACKEND_URL=http://backend:5001
```

### Backend service

```text
APP_HOST=0.0.0.0
APP_PORT=5001
HISTORY_URL=http://history:5002
```

### History service

```text
APP_HOST=0.0.0.0
APP_PORT=5002
DATABASE_URL=postgresql://weather_user:weather_password@postgres:5432/weather_history
```

### PostgreSQL

```text
POSTGRES_DB=weather_history
POSTGRES_USER=weather_user
POSTGRES_PASSWORD=weather_password
```

The credentials in `docker-compose.yml` are intended for local development and learning purposes only.

## PostgreSQL data

PostgreSQL data is stored in the named Docker volume:

```text
postgres_data
```

This allows the database data to remain available after running:

```bash
docker compose down
```

## Useful commands

```bash
# Validate docker-compose.yml
docker compose config

# Build application images
docker compose build

# Start all services
docker compose up -d

# Build and start all services
docker compose up -d --build

# Display running services
docker compose ps

# Display logs
docker compose logs -f

# Stop the project
docker compose down

# Stop the project and remove database data
docker compose down -v
```