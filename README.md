# Weather App — Weather Monitoring in Nadvirna

A web application for automatically collecting, storing, and displaying weather data (current conditions, a 24-hour forecast, and history for the past 24 hours or 7 days) for **Nadvirna**.

![current/forecast](https://github.com/ua-academy-projects/push-and-pray/blob/f7be1459605a687fb120fa1a9aa51b5679e8cd83/current_weather_and_forecast.png)
![history](https://github.com/ua-academy-projects/push-and-pray/blob/f7be1459605a687fb120fa1a9aa51b5679e8cd83/weather_history.png)
![archive](https://github.com/ua-academy-projects/push-and-pray/blob/f7be1459605a687fb120fa1a9aa51b5679e8cd83/archive.png)
---

## 🏛 Architecture

```text
Browser
   │
   ▼
ui-service.local:5000 ───────────────► backend-service.local:5001
   │                                      │
   │                                      ├──► PostgreSQL
   ▼                                      │     database.local:5432
Redis                                     │
database.local:6379                       ◄── RabbitMQ
                                               database.local:5672
                                                    ▲
                                                    │ publish
Open-Meteo API ◄────► provider-service.local:5002 ──┘
```

- **`ui-service VM`** (`ui-service.local`, `ui-service` container, port `5000`):
  - Serves the HTML/CSS/JS interface.
  - Manages user sessions through Redis at `database.local:6379`.
  - Proxies `/api/*` weather requests to the Backend Service at `backend-service.local:5001`.

- **`backend-service VM`** (`backend-service.local`, `backend-service` container, port `5001`):
  - Asynchronously consumes weather messages from RabbitMQ at `database.local:5672`.
  - Stores weather data in PostgreSQL at `database.local:5432`.
  - Provides the following API endpoints: `/api/weather`, `/api/forecast`, and `/api/history?hours=24|168`.

- **`provider-service VM`** (`provider-service.local`, `provider-service` container, port `5002`):
  - Periodically queries the Open-Meteo API.
  - Publishes weather data updates to RabbitMQ at `database.local:5672`.

- **`database VM`** (`database.local`, Docker Compose):
  - **`PostgreSQL 16`** (`5432`): Stores hourly data points in the unified `weather_hourly_points` table.
  - **`Redis 7`** (`6379`): Stores UI user sessions with `appendonly yes` persistence enabled.
  - **`RabbitMQ 3`** (`5672`, Web UI `15672`): Handles asynchronous messaging.

Each Compose project runs on a separate VM. Container services listen on
`0.0.0.0`, and their ports are published through the VM's bridged interface
without being bound to a specific DHCP address.

---

## 📁 Project Structure

```text
weather-app/
├── backend-service/
│   ├── app.py
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── migrations/
│   │   └── 001_unified_hourly_weather.sql
│   └── tests/
├── provider-service/
│   ├── app.py
│   ├── Dockerfile
│   ├── requirements.txt
│   └── tests/
├── ui-service/
│   ├── app.py
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── static/
│   │   ├── script.js
│   │   └── style.css
│   ├── templates/
│   │   └── index.html
│   └── tests/
├── infrastructure/
│   ├── compose/
│   │   ├── backend-service.yml
│   │   ├── database-service.yml
│   │   ├── provider-service.yml
│   │   └── ui-service.yml
│   └── vagrant/
│       ├── Vagrantfile
│       └── provisioning/
│           ├── backend.sh
│           ├── common.sh
│           ├── database.sh
│           ├── provider.sh
│           └── ui.sh
├── tests/
├── .env.example
├── requirements-test.txt
├── Vagrantfile              # root entry point
├── README.md
└── LICENSE
```

The code, Dockerfile, dependencies, and local tests for each Python service
remain in that service's directory. All operational configuration is grouped
under `infrastructure/`, and each VM runs only its own Compose project.
The root `Vagrantfile` loads the main configuration from
`infrastructure/vagrant/Vagrantfile`, so all Vagrant commands must be run from
the project root. After changing the network configuration, destroy any
previously created VMs with `vagrant destroy -f` and recreate them.

The provisioning scripts install Docker, Docker Compose, Avahi, and
`libnss-mdns`; automatically create a Linux user matching the host's username
(`$USER`) with SSH public key authentication and membership in `sudo` and `docker`
groups; open the required UFW ports when the firewall is active; resolve the
current IPv4 addresses of dependent VMs through their `.local` names; and pass
those addresses to Compose through environment variables. DHCP addresses are not
hard-coded in the Compose files.

---

## 🚀 Deployment with Vagrant (VMware Fusion / Desktop)

Inside each VM, the corresponding part of the project runs in an isolated Docker container through Docker Compose.

Before startup, VMware `vmnet0` must be bridged to the physical interface of
the local network. The router must provide IPv4 addresses through DHCP, and all
four VMs must be on the same LAN.

### Start and Check VM Status

```bash
# Start all four VMs and run automatic provisioning
vagrant up

# Check VM status
vagrant status

# Validate the Vagrantfile
vagrant validate
```

The VMs are declared in dependency order: `database`, `provider-service`,
`backend-service`, and `ui-service`. Provisioning runs during each `vagrant up`;
dependent VMs wait until the required `.local` names can be resolved.

If necessary, the VMs can be started individually in the same order:

```bash
vagrant up database
vagrant up provider-service
vagrant up backend-service
vagrant up ui-service
```

### Check Container Status on Each VM

```bash
# Database VM (PostgreSQL, Redis, RabbitMQ)
vagrant ssh database -c "docker compose -f /vagrant/infrastructure/compose/database-service.yml ps"

# Provider VM
vagrant ssh provider-service -c "docker compose -f /vagrant/infrastructure/compose/provider-service.yml ps"

# Backend VM
vagrant ssh backend-service -c "docker compose -f /vagrant/infrastructure/compose/backend-service.yml ps"

# UI VM
vagrant ssh ui-service -c "docker compose -f /vagrant/infrastructure/compose/ui-service.yml ps"
```

### View Container Logs (journald, Docker Compose, Docker)

All service and container logs are routed through Docker's `journald` logging driver into systemd's `journald` on each VM.

#### 1. Via `journalctl` (Systemd Journal)

Query logs directly from systemd `journald` on any VM:

```bash
# Follow live logs for backend container via journalctl
vagrant ssh backend-service -c "sudo journalctl CONTAINER_NAME=backend-service-backend-service-1 -f"

# View last 100 log entries for provider service via journalctl
vagrant ssh provider-service -c "sudo journalctl CONTAINER_NAME=provider-service-provider-service-1 -n 100"

# View logs for database container on database VM via journalctl
vagrant ssh database -c "sudo journalctl CONTAINER_NAME=database-service-database-1 -n 50"
```

#### 2. Via `docker compose logs`

```bash
# Database VM (PostgreSQL, Redis, RabbitMQ)
vagrant ssh database -c "docker compose -f /vagrant/infrastructure/compose/database-service.yml logs --tail=100"

# Provider VM
vagrant ssh provider-service -c "docker compose -f /vagrant/infrastructure/compose/provider-service.yml logs --tail=100"

# Backend VM
vagrant ssh backend-service -c "docker compose -f /vagrant/infrastructure/compose/backend-service.yml logs --tail=100"

# UI VM
vagrant ssh ui-service -c "docker compose -f /vagrant/infrastructure/compose/ui-service.yml logs --tail=100"
```

#### 3. Via `docker logs`

```bash
# View logs directly via docker logs using container name or ID
vagrant ssh backend-service -c "docker logs --tail=100 backend-service-backend-service-1"
vagrant ssh ui-service -c "docker logs -f ui-service-ui-service-1"
```

---

## 🌐 Network, DHCP, and mDNS

Each VM has one VMware `ethernet0` adapter:

- the connection type is `bridged` through `vmnet0`;
- the local router's DHCP server assigns the IPv4 address;
- NAT, private/host-only networks, and forwarded ports are not used;
- Vagrant SSH and provisioning use the bridged DHCP address;
- additional VMware adapters are disabled.

Stable network names are published through Avahi/mDNS:

| VM       | mDNS hostname            | Containers and published ports                                          |
| -------- | ------------------------ | ----------------------------------------------------------------------- |
| UI       | `ui-service.local`       | UI `5000`                                                               |
| Backend  | `backend-service.local`  | Backend API `5001`                                                      |
| Provider | `provider-service.local` | Provider API `5002`                                                     |
| Database | `database.local`         | PostgreSQL `5432`, Redis `6379`, RabbitMQ `5672`, Management UI `15672` |

Provisioning resolves these names to their current LAN IPv4 addresses while
ignoring loopback and link-local addresses, then passes them to the appropriate
Compose projects as `BACKEND_IP`, `PROVIDER_IP`, and `DATABASE_IP`.

### View VM LAN IPv4 Addresses

The commands below display global IPv4 addresses without the `docker0` and
Docker bridge interfaces:

```bash
vagrant ssh ui-service -c "ip -4 -o addr show scope global | awk '\$2 !~ /^(docker0|br-)/ {print \$2, \$4}'"
vagrant ssh backend-service -c "ip -4 -o addr show scope global | awk '\$2 !~ /^(docker0|br-)/ {print \$2, \$4}'"
vagrant ssh provider-service -c "ip -4 -o addr show scope global | awk '\$2 !~ /^(docker0|br-)/ {print \$2, \$4}'"
vagrant ssh database -c "ip -4 -o addr show scope global | awk '\$2 !~ /^(docker0|br-)/ {print \$2, \$4}'"
```

---

## 🔑 Custom SSH User and Access

### Automatic User & SSH Key Provisioning

During `vagrant up` provisioning, `Vagrantfile` and `infrastructure/vagrant/provisioning/common.sh` automatically configure user access:

1. **Host Detection (`Vagrantfile`)**:
   - Detects your local host machine's username (`$USER` / `id -un`).
   - Automatically finds and reads your host's SSH public key (`~/.ssh/id_ed25519.pub`, `~/.ssh/id_rsa.pub`, or `~/.ssh/id_ecdsa.pub`). If no key is found, `vagrant up` halts with an informative error message.
   - Passes `HOST_USER` and `HOST_SSH_KEY` environment variables to the provisioning scripts.

2. **VM Provisioning (`common.sh`)**:
   - Creates a Linux user matching your host username on each VM (`adduser --disabled-password --gecos ""`).
   - Safely adds the user to the `sudo` and `docker` groups (if present).
   - Injects your public SSH key into `~/.ssh/authorized_keys` with strict permissions (`0700` for `~/.ssh`, `0600` for `authorized_keys`).
   - All operations are fully idempotent and preserve the default `vagrant` user.

### Connecting to VMs

You can connect to any VM via standard Vagrant SSH:

```bash
vagrant ssh database
vagrant ssh backend-service
```

Or connect directly as your host user via mDNS without entering a password:

```bash
ssh <your-host-username>@database.local
ssh <your-host-username>@backend-service.local
```

### Using Repository SSH Config (`.ssh/config`)

The repository includes a `.ssh/config` file with host aliases (`db`, `provider`, `backend`, `ui`).

**Option 1: Pass config via `-F`**
```bash
ssh -F .ssh/config db
ssh -F .ssh/config ui
```

**Option 2: Include in your global `~/.ssh/config`**
Add the following line to the top of your `~/.ssh/config`:
```sshconfig
Include /path/to/weather-app/.ssh/config
```

Then connect directly using short aliases from anywhere:
```bash
ssh db
ssh provider
ssh backend
ssh ui
```

---

## 💻 Web UI and RabbitMQ Management Access

### UI Access

- **Via mDNS:** [http://ui-service.local:5000](http://ui-service.local:5000)
- **Via the current DHCP address:** `http://<UI_DHCP_IP>:5000`

### RabbitMQ Management UI Access

- **Via mDNS:** [http://database.local:15672](http://database.local:15672)
- **Via the current DHCP address:** `http://<DATABASE_DHCP_IP>:15672`

Access through `localhost:8080` is unavailable because port forwarding is no
longer configured.

**RabbitMQ credentials:**

- **Username:** `weather_user`
- **Password:** `weather_password`

---

## 🗄 Check the Database (PostgreSQL in a Container)

Because PostgreSQL runs in a Docker container, use `docker compose exec` to run SQL queries:

```bash
# Connect to psql inside the PostgreSQL container on the database VM
vagrant ssh database -c "docker compose -f /vagrant/infrastructure/compose/database-service.yml exec database psql -U weather_user -d weather_history"
```

The database Compose project remains named `database-service`, and PostgreSQL
continues to use the existing `database-service_postgres_data` Docker volume.
Moving the YAML file does not create a new volume or delete existing data.

Example query for checking records in the psql console:

```sql
SELECT weather_at, temperature, data_kind, fetched_at FROM weather_hourly_points ORDER BY weather_at DESC LIMIT 10;
```

---

## 🧪 Testing

Run all automated tests from the project root:

```bash
python3 -m pytest -q
```
