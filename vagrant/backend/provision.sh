#!/usr/bin/env bash
# Provisions the backend-service VM: Python 3.12, the service's venv, a .env
# pointed at the postgres VM, migrations, and a systemd unit to run it.
#
# Networking note: all VMs are bridged onto the host's LAN (see Vagrantfile),
# each with its own fixed IP - this guest reaches postgres (and Redis, on the
# same VM) directly at its bridged IP, no NAT/slirp gateway needed. There is
# no forwarded-port fallback to localhost for any service, so
# BACKEND_CORS_ORIGINS is set to the ui-service VM's own LAN IP - every
# browser that loads the UI, on this Mac or any other device, does so from
# that address, and that's what its Origin header will carry.
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
RABBITMQ_USER="skyivano"
RABBITMQ_PASS="skyivano"

export DEBIAN_FRONTEND=noninteractive

echo ">>> Installing Python 3.12"
apt-get update -y
apt-get install -y software-properties-common curl
add-apt-repository -y ppa:deadsnakes/ppa
apt-get update -y
apt-get install -y python3.12 python3.12-venv python3.12-dev

echo ">>> Waiting for postgres (${POSTGRES_IP}:5432) to accept connections"
apt-get install -y postgresql-client
for i in $(seq 1 30); do
  if PGPASSWORD="${DB_PASS}" psql -h "${POSTGRES_IP}" -U "${DB_USER}" -d "${DB_NAME}" -c "SELECT 1" >/dev/null 2>&1; then
    echo "    postgres is up"
    break
  fi
  echo "    attempt ${i}/30: not ready yet, retrying in 2s"
  sleep 2
done

echo ">>> Waiting for redis (${REDIS_IP}:6379) to accept connections"
apt-get install -y redis-tools
for i in $(seq 1 30); do
  if redis-cli -h "${REDIS_IP}" ping 2>/dev/null | grep -q PONG; then
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

echo ">>> Setting up backend-service"
cd "${APP_DIR}"
python3.12 -m venv .venv
./.venv/bin/pip install --upgrade pip
./.venv/bin/pip install -r requirements.txt
[ -f .env ] || cp .env.example .env
sed -i "s#^DATABASE_URL=.*#DATABASE_URL=postgresql+psycopg://${DB_USER}:${DB_PASS}@${POSTGRES_IP}:5432/${DB_NAME}#" .env
sed -i "s#^FETCHER_SERVICE_BASE_URL=.*#FETCHER_SERVICE_BASE_URL=http://${FETCHER_IP}:8002#" .env
sed -i "s#^REDIS_URL=.*#REDIS_URL=redis://${REDIS_IP}:6379/0#" .env
sed -i "s#^RABBITMQ_URL=.*#RABBITMQ_URL=amqp://${RABBITMQ_USER}:${RABBITMQ_PASS}@${RABBITMQ_IP}:5672/#" .env
sed -i "s#^BACKEND_CORS_ORIGINS=.*#BACKEND_CORS_ORIGINS=http://${UI_IP}:5173#" .env
./.venv/bin/alembic upgrade head

echo ">>> Installing systemd units"
cat > /etc/systemd/system/backend-service.service <<'EOF'
[Unit]
Description=SkyIvano Backend Service
After=network.target

[Service]
Type=simple
User=vagrant
WorkingDirectory=/app
EnvironmentFile=/app/.env
ExecStart=/app/.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# A separate process from the API above -- consumes weather.sync / weather.sync_failure
# from RabbitMQ and persists via the same app/services/persistence_service.py the API uses.
# See app/broker/consumer.py and app/worker.py.
cat > /etc/systemd/system/backend-worker.service <<'EOF'
[Unit]
Description=SkyIvano Backend Worker (RabbitMQ consumer)
After=network.target

[Service]
Type=simple
User=vagrant
WorkingDirectory=/app
EnvironmentFile=/app/.env
ExecStart=/app/.venv/bin/python -m app.worker
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

chown -R vagrant:vagrant "${APP_DIR}/.venv"
systemctl daemon-reload
systemctl enable --now backend-service
systemctl enable --now backend-worker

echo ">>> Provisioning complete"
echo "    Backend Service reachable at 192.168.0.221:8000 on the LAN"
echo "    Backend Worker (RabbitMQ consumer) running as its own systemd service (backend-worker)"
