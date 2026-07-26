# AirAware

AirAware is a multi-service air-quality monitoring application that collects hourly air-quality data for a predefined set of cities, stores the measurements in PostgreSQL, and displays current and historical values in a web dashboard.

The project is deployed with Vagrant across four separate virtual machines connected to the local home network through bridged networking.

## Features

- Hourly air-quality data collection from Open-Meteo
- Preconfigured list of Ukrainian cities
- Current air-quality metrics for each city
- 12-hour and 24-hour historical views
- City switcher in the dashboard
- PostgreSQL time-series storage
- Duplicate measurement prevention
- Health and readiness endpoints
- Automated deployment with Vagrant
- Separate VMs for Frontend, Backend, API Fetcher, and PostgreSQL

## Architecture

```text
                             Internet
                                |
                                v
                     Open-Meteo Air Quality API
                                ^
                                |
                  API Fetcher VM — 192.168.50.212
                                |
                                | POST /api/measurements
                                v
Frontend VM ----------> Backend VM ----------> Database VM
192.168.50.210          192.168.50.211         192.168.50.213
      |                       |                       |
      |                       |                       |
Browser access         FastAPI Backend          PostgreSQL
Flask dashboard        Data access layer        Persistent storage
```

The main communication rules are:

- The Frontend communicates only with the Backend.
- The API Fetcher communicates with Open-Meteo and the Backend.
- The Backend is the only component that connects to PostgreSQL.
- Services communicate through VM LAN addresses, not `localhost`.

More details are available in [docs/architecture.md](docs/architecture.md).

## Components

### Frontend Service

- Technology: Flask, HTML, CSS, JavaScript
- VM address: `192.168.50.210`
- Port: `5000`
- Purpose: displays current and historical air-quality information

### Backend Service

- Technology: FastAPI, SQLAlchemy, Psycopg
- VM address: `192.168.50.211`
- Port: `8001`
- Purpose: validates, stores, and returns air-quality measurements

### API Fetcher Service

- Technology: FastAPI, HTTPX, APScheduler
- VM address: `192.168.50.212`
- Port: `8000`
- Purpose: retrieves measurements from Open-Meteo every hour and sends them to the Backend

### Database Service

- Technology: PostgreSQL
- VM address: `192.168.50.213`
- Port: `5432`
- Purpose: stores configured cities and hourly measurements

## Repository structure

```text
AIRAWARE/
├── api-fetcher-service/
├── backend-service/
│   └── database/
│       └── init.sql
├── frontend-service/
├── provision/
│   ├── common.sh
│   ├── application.sh
│   └── database.sh
├── docs/
│   ├── architecture.md
│   ├── deployment-vagrant.md
│   ├── operations.md
│   └── troubleshooting.md
├── Vagrantfile
├── .gitattributes
├── .gitignore
└── README.md
```

## Prerequisites

- Git
- Vagrant 2.4 or newer
- VirtualBox 7.x
- A local network that allows devices to communicate with one another
- Four unused IP addresses on the same local subnet
- At least 4 GB of available RAM for the VMs

The current configuration uses:

```text
Network:  192.168.50.0/24
Gateway:  192.168.50.1
Bridge:   Intel(R) Wi-Fi 6 AX200 160MHz
```

VM addresses:

| Component | Address | Port |
|---|---:|---:|
| Frontend | `192.168.50.210` | `5000` |
| Backend | `192.168.50.211` | `8001` |
| API Fetcher | `192.168.50.212` | `8000` |
| PostgreSQL | `192.168.50.213` | `5432` |

Before deployment, confirm that these addresses are unused and are not assigned dynamically by the router.

## Quick start

From PowerShell in the repository root:

```powershell
$env:AIRAWARE_DB_PASSWORD = "replace-with-a-strong-password"
vagrant validate
vagrant up --provider=virtualbox
```

Check the environment:

```powershell
vagrant status
```

Expected result:

```text
database   running (virtualbox)
backend    running (virtualbox)
fetcher    running (virtualbox)
frontend   running (virtualbox)
```

Open the application:

```text
http://192.168.50.210:5000
```

Backend documentation:

```text
http://192.168.50.211:8001/docs
```

Fetcher documentation:

```text
http://192.168.50.212:8000/docs
```

## Environment overrides

The Vagrant configuration can be changed through environment variables.

Example:

```powershell
$env:AIRAWARE_NETWORK_PREFIX = "192.168.88"
$env:AIRAWARE_NETMASK = "255.255.255.0"
$env:AIRAWARE_BRIDGE_ADAPTER = "Intel(R) Wi-Fi 6 AX200 160MHz"
$env:AIRAWARE_DB_PASSWORD = "replace-with-a-strong-password"

vagrant up
```

When changing to another local network, ensure the VM addresses are valid and unused on that subnet.

## Common commands

Start all VMs:

```powershell
vagrant up
```

Stop all VMs safely:

```powershell
vagrant halt
```

Show status:

```powershell
vagrant status
```

Connect to a VM:

```powershell
vagrant ssh backend
```

Reprovision one service:

```powershell
vagrant provision backend
```

Destroy all VMs:

```powershell
vagrant destroy -f
```

Destroying the Database VM removes all PostgreSQL data stored inside it.

## API summary

### Backend Service

```text
GET  /health
GET  /health/ready
GET  /api/cities
POST /api/measurements
GET  /api/dashboard?city=kyiv&hours=24
```

### API Fetcher Service

```text
GET  /health
GET  /health/ready
GET  /fetch/status
POST /fetch
```

### Frontend Service

```text
GET /health
GET /health/ready
GET /api/cities
GET /api/dashboard?city=kyiv&hours=24
```

## Data collection

The API Fetcher:

- performs an optional fetch at startup;
- runs every hour at a configured minute;
- fetches all active cities concurrently;
- sends measurements to the Backend;
- does not connect directly to PostgreSQL.

The database prevents duplicate measurements through a unique constraint on city and observation time.

## Documentation

- [Architecture](docs/architecture.md)
- [Vagrant deployment](docs/deployment-vagrant.md)
- [Operations guide](docs/operations.md)
- [Troubleshooting](docs/troubleshooting.md)
