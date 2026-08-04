#!/usr/bin/env bash
# Provisions the backend-service VM: installs Docker Engine + the Compose plugin,
# writes a .env pointed at the postgres VM, and runs `docker compose up -d --build`
# against backend-service/docker-compose.yml (a single `api` container -- its RabbitMQ
# consumer runs as a background task in that same process, see app/main.py's lifespan;
# see docs/architecture.md §17, decision 27 for history). It creates any missing tables
# itself on startup (app.database.session.init_db) -- no migration step.
#
# Networking note: all VMs are bridged onto the host's LAN (see Vagrantfile), each
# with its own fixed IP - this guest reaches postgres (and Redis/RabbitMQ, on the
# same VM) directly at its bridged IP. Every container here uses
# network_mode: host, so it binds to this VM's own bridged IP -- BACKEND_CORS_ORIGINS
# is set to the ui-service VM's own LAN IP for the same reason it always was: every
# browser that loads the UI does so from that address, and that's what its Origin
# header will carry.
set -euo pipefail

APP_DIR="/app"
POSTGRES_IP="192.168.0.220"
REDIS_IP="192.168.0.220" # same VM as postgres -- see vagrant/postgres/provision.sh
RABBITMQ_IP="192.168.0.220" # same VM as postgres -- see vagrant/postgres/provision.sh
FETCHER_IP="192.168.0.222"
UI_IP="192.168.0.223"
DB_USER="skyivano"
DB_PASS="skyivano"
DB_NAME="skyivano"
REDIS_PASS="skyivano"
RABBITMQ_USER="skyivano"
RABBITMQ_PASS="skyivano"

export DEBIAN_FRONTEND=noninteractive

# Ubuntu's unattended-upgrades runs automatically shortly after boot and holds the
# dpkg lock while it does; without -o DPkg::Lock::Timeout, apt-get fails immediately
# instead of waiting for it, making provisioning fail intermittently depending on how
# the timing lands. 300s comfortably outlasts a typical unattended-upgrades run.
APT="apt-get -o DPkg::Lock::Timeout=300"

if ! command -v docker >/dev/null 2>&1; then
  echo ">>> Installing Docker Engine + Compose plugin"
  $APT update -y
  $APT install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  ARCH="$(dpkg --print-architecture)"
  CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"
  echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  $APT update -y
  $APT install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  systemctl enable --now docker
  usermod -aG docker vagrant
fi

echo ">>> Creating sky user (docker group member)"
if ! id -u sky >/dev/null 2>&1; then
  useradd -m -s /bin/bash sky
  install -d -m 700 -o sky -g sky /home/sky/.ssh
  echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILzfD7LC8tdDbnpi5ozVF3Jsws3GNL0DXkF8bljj4avI sky@vagrant-vms" > /home/sky/.ssh/authorized_keys
  chmod 600 /home/sky/.ssh/authorized_keys
  chown sky:sky /home/sky/.ssh/authorized_keys
fi
usermod -aG docker sky

echo ">>> Waiting for postgres (${POSTGRES_IP}:5432) to accept connections"
$APT install -y postgresql-client
for i in $(seq 1 30); do
  if PGPASSWORD="${DB_PASS}" psql -h "${POSTGRES_IP}" -U "${DB_USER}" -d "${DB_NAME}" -c "SELECT 1" >/dev/null 2>&1; then
    echo "    postgres is up"
    break
  fi
  echo "    attempt ${i}/30: not ready yet, retrying in 2s"
  sleep 2
done

echo ">>> Waiting for redis (${REDIS_IP}:6379) to accept connections"
$APT install -y redis-tools
for i in $(seq 1 30); do
  if redis-cli -h "${REDIS_IP}" -a "${REDIS_PASS}" --no-auth-warning ping 2>/dev/null | grep -q PONG; then
    echo "    redis is up"
    break
  fi
  echo "    attempt ${i}/30: not ready yet, retrying in 2s"
  sleep 2
done

echo ">>> Waiting for rabbitmq (${RABBITMQ_IP}:5672) to accept connections"
for i in $(seq 1 30); do
  if (exec 3<>"/dev/tcp/${RABBITMQ_IP}/5672") 2>/dev/null; then
    exec 3<&- 3>&-
    echo "    rabbitmq is up"
    break
  fi
  echo "    attempt ${i}/30: not ready yet, retrying in 2s"
  sleep 2
done

echo ">>> Writing ${APP_DIR}/.env"
cd "${APP_DIR}"
[ -f .env ] || cp .env.example .env
sed -i "s#^DATABASE_URL=.*#DATABASE_URL=postgresql+psycopg://${DB_USER}:${DB_PASS}@${POSTGRES_IP}:5432/${DB_NAME}#" .env
sed -i "s#^FETCHER_SERVICE_BASE_URL=.*#FETCHER_SERVICE_BASE_URL=http://${FETCHER_IP}:8002#" .env
sed -i "s#^REDIS_URL=.*#REDIS_URL=redis://:${REDIS_PASS}@${REDIS_IP}:6379/0#" .env
sed -i "s#^RABBITMQ_URL=.*#RABBITMQ_URL=amqp://${RABBITMQ_USER}:${RABBITMQ_PASS}@${RABBITMQ_IP}:5672/#" .env
sed -i "s#^BACKEND_CORS_ORIGINS=.*#BACKEND_CORS_ORIGINS=http://${UI_IP}:5173#" .env

echo ">>> Starting backend-service (api)"
docker compose up -d --build

echo ">>> Provisioning complete"
echo "    Backend Service (api container, API + RabbitMQ consumer) reachable at 192.168.0.221:8000 on the LAN"
