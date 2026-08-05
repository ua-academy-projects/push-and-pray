# AirAware

AirAware is a four-VM air-quality monitoring system. It collects measurements from Open-Meteo, publishes them through RabbitMQ, stores them in PostgreSQL, and displays current and historical values in a Flask dashboard.

Vagrant creates and networks the Ubuntu VMs. Docker Compose runs every application and infrastructure service inside those VMs.

## Architecture

```text
Open-Meteo
    |
    v
API Fetcher -----> RabbitMQ -----> Backend consumer -----> PostgreSQL
    |                                      ^
    | reads active cities                  |
    +--------------> Backend API <---------+---- Frontend
```

Default bridged-LAN endpoints:

| VM | Address | Published services |
|---|---:|---|
| Frontend | `192.168.18.210` | Flask dashboard on `5000` |
| Backend | `192.168.18.211` | FastAPI on `8001` |
| Fetcher | `192.168.18.212` | FastAPI on `8000` |
| Database | `192.168.18.213` | PostgreSQL `5432`, Redis `6379`, RabbitMQ `5672` and management UI `15672` |

The frontend stores UI preferences in Flask signed-cookie sessions. Redis remains deployed as a persistent, password-protected infrastructure service, but it is not the frontend session store.

See [Architecture](docs/architecture.md) for the complete data and failure flows.

## Prerequisites

- Git
- Vagrant 2.4 or newer
- VirtualBox 7.x
- Four unused addresses on the active LAN
- At least 5 GB of host memory available for the VMs and VirtualBox overhead; 6 GB is recommended during initial image builds

The fixed VM allocation is 3968 MB: 2048 MB for the infrastructure VM and 640 MB for each application VM.

## Configure

Create the local configuration from the example:

```powershell
Copy-Item .env.example .env
```

Edit `.env` and set:

- the active LAN prefix and exact VirtualBox bridge-adapter name;
- strong, distinct PostgreSQL, Redis, RabbitMQ, and Flask secrets;
- an optional SSH public-key path.

The root `.env` file and generated Compose `.env` files are ignored by Git. Do not commit them.

## Deploy

Validate first:

```powershell
vagrant validate
```

Start the environment in dependency order:

```powershell
vagrant up database
vagrant up backend
vagrant up fetcher
vagrant up frontend
```

`vagrant up` also starts the full multi-machine environment.

Provisioning copies only required source files, builds or pulls images, waits up to 180 seconds for containers to become healthy, and applies pending PostgreSQL migrations. Deployment fails with container status and recent logs if readiness is not reached.

## Verify

```powershell
curl.exe http://192.168.18.210:5000/health/ready
curl.exe http://192.168.18.211:8001/health/ready
curl.exe http://192.168.18.212:8000/health/ready
curl.exe -X POST http://192.168.18.212:8000/fetch
```

Open the dashboard at `http://192.168.18.210:5000`.

Open API documentation at:

- `http://192.168.18.211:8001/docs`
- `http://192.168.18.212:8000/docs`

Open RabbitMQ management at `http://192.168.18.213:15672`.

## Common commands

```powershell
vagrant status
vagrant ssh backend
vagrant provision backend --provision-with compose
vagrant halt
```

Reprovision only the VM whose source or Compose configuration changed. Database provisioning also runs every pending numbered SQL migration.

Before destroying the database VM, create a PostgreSQL backup. `vagrant destroy database -f` deletes the VM disk and all named Docker volumes stored on it.

## Repository structure

```text
AirAware/
├── api-fetcher-service/
├── backend-service/
│   └── database/migrations/
├── frontend-service/
├── deploy/
│   ├── backend/
│   ├── fetcher/
│   ├── frontend/
│   └── infrastructure/
├── provision/
├── ssh/
├── docs/
├── Vagrantfile
└── .env.example
```

## Documentation

- [Architecture](docs/architecture.md)
- [Vagrant deployment](docs/deployment-vagrant.md)
- [Docker Compose deployment](docs/deployment-docker.md)
- [Operations](docs/operations.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Optional SSH access](ssh/README.md)
