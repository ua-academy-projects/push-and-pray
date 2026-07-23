#!/usr/bin/env bash
# Provisions the backend-service VM: Python 3.12, the service's venv, a .env
# pointed at the history-service VM, and a systemd unit to run it.
#
# Networking note: there is no private LAN between the VMs (see Vagrantfile).
# This guest reaches history-service via its own slirp gateway alias
# (10.0.2.2), which the real host then routes to history-service's forwarded
# port 8001. BACKEND_CORS_ORIGINS is left at its .env.example default
# (http://localhost:5173) - the browser making the request runs on the host,
# so its Origin header is localhost:5173 regardless of how the guests talk
# to each other.
set -euo pipefail

APP_DIR="/app"
GATEWAY="10.0.2.2"

export DEBIAN_FRONTEND=noninteractive

echo ">>> Installing Python 3.12"
apt-get update -y
apt-get install -y software-properties-common curl
add-apt-repository -y ppa:deadsnakes/ppa
apt-get update -y
apt-get install -y python3.12 python3.12-venv python3.12-dev

echo ">>> Waiting for history-service (${GATEWAY}:8001) to respond"
for i in $(seq 1 30); do
  if curl -fsS -o /dev/null "http://${GATEWAY}:8001/docs"; then
    echo "    history-service is up"
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
sed -i "s#^HISTORY_SERVICE_BASE_URL=.*#HISTORY_SERVICE_BASE_URL=http://${GATEWAY}:8001#" .env

echo ">>> Installing systemd unit"
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

chown -R vagrant:vagrant "${APP_DIR}/.venv"
systemctl daemon-reload
systemctl enable --now backend-service

echo ">>> Provisioning complete"
echo "    Backend Service reachable at localhost:8000 on the host, or ${GATEWAY}:8000 from other VMs"
