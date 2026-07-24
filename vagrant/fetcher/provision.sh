#!/usr/bin/env bash
# Provisions the fetcher-service VM: Python 3.12, the service's venv, a .env
# pointed at the backend-service VM, and a systemd unit to run it.
#
# Networking note: all VMs are bridged onto the host's LAN (see Vagrantfile),
# each with its own fixed IP - this guest reaches backend-service directly
# at its bridged IP, no NAT/slirp gateway needed. The Fetcher never touches
# PostgreSQL directly (see docs/architecture.md), so there's nothing here
# pointed at the postgres VM.
set -euo pipefail

APP_DIR="/app"
BACKEND_IP="192.168.0.221"

export DEBIAN_FRONTEND=noninteractive

echo ">>> Installing Python 3.12"
apt-get update -y
apt-get install -y software-properties-common curl
add-apt-repository -y ppa:deadsnakes/ppa
apt-get update -y
apt-get install -y python3.12 python3.12-venv python3.12-dev

echo ">>> Waiting for backend-service (${BACKEND_IP}:8000) to respond"
for i in $(seq 1 30); do
  if curl -fsS -o /dev/null "http://${BACKEND_IP}:8000/docs"; then
    echo "    backend-service is up"
    break
  fi
  echo "    attempt ${i}/30: not ready yet, retrying in 2s"
  sleep 2
done

echo ">>> Setting up fetcher-service"
cd "${APP_DIR}"
python3.12 -m venv .venv
./.venv/bin/pip install --upgrade pip
./.venv/bin/pip install -r requirements.txt
[ -f .env ] || cp .env.example .env
sed -i "s#^BACKEND_INTERNAL_BASE_URL=.*#BACKEND_INTERNAL_BASE_URL=http://${BACKEND_IP}:8000#" .env

echo ">>> Installing systemd unit"
cat > /etc/systemd/system/fetcher-service.service <<'EOF'
[Unit]
Description=SkyIvano Weather Fetcher Service
After=network.target

[Service]
Type=simple
User=vagrant
WorkingDirectory=/app
EnvironmentFile=/app/.env
ExecStart=/app/.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8002
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

chown -R vagrant:vagrant "${APP_DIR}/.venv"
systemctl daemon-reload
systemctl enable --now fetcher-service

echo ">>> Provisioning complete"
echo "    Fetcher Service reachable at 192.168.0.222:8002 on the LAN"
