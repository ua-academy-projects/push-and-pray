#!/usr/bin/env bash
# Provisions the history-service VM: Python 3.12, the service's venv, a .env
# pointed at the postgres VM, migrations, and a systemd unit to run it.
#
# Networking note: there is no private LAN between the VMs (see Vagrantfile).
# This guest reaches postgres via its own slirp gateway alias (10.0.2.2),
# which the real host then routes to postgres's forwarded port 5432.
set -euo pipefail

APP_DIR="/app"
GATEWAY="10.0.2.2"
DB_USER="skyivano"
DB_PASS="skyivano"
DB_NAME="skyivano"

export DEBIAN_FRONTEND=noninteractive

echo ">>> Installing Python 3.12"
apt-get update -y
apt-get install -y software-properties-common curl
add-apt-repository -y ppa:deadsnakes/ppa
apt-get update -y
apt-get install -y python3.12 python3.12-venv python3.12-dev

echo ">>> Waiting for postgres (${GATEWAY}:5432) to accept connections"
apt-get install -y postgresql-client
for i in $(seq 1 30); do
  if PGPASSWORD="${DB_PASS}" psql -h "${GATEWAY}" -U "${DB_USER}" -d "${DB_NAME}" -c "SELECT 1" >/dev/null 2>&1; then
    echo "    postgres is up"
    break
  fi
  echo "    attempt ${i}/30: not ready yet, retrying in 2s"
  sleep 2
done

echo ">>> Setting up history-service"
cd "${APP_DIR}"
python3.12 -m venv .venv
./.venv/bin/pip install --upgrade pip
./.venv/bin/pip install -r requirements.txt
[ -f .env ] || cp .env.example .env
sed -i "s#^DATABASE_URL=.*#DATABASE_URL=postgresql+psycopg://${DB_USER}:${DB_PASS}@${GATEWAY}:5432/${DB_NAME}#" .env
./.venv/bin/alembic upgrade head

echo ">>> Installing systemd unit"
cat > /etc/systemd/system/history-service.service <<'EOF'
[Unit]
Description=SkyIvano History Service
After=network.target

[Service]
Type=simple
User=vagrant
WorkingDirectory=/app
EnvironmentFile=/app/.env
ExecStart=/app/.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8001
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

chown -R vagrant:vagrant "${APP_DIR}/.venv"
systemctl daemon-reload
systemctl enable --now history-service

echo ">>> Provisioning complete"
echo "    History Service reachable at localhost:8001 on the host, or ${GATEWAY}:8001 from other VMs"
