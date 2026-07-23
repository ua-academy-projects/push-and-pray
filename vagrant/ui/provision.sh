#!/usr/bin/env bash
# Provisions the ui-service VM: Node.js LTS, npm install, and a systemd unit
# to run the Vite dev server.
#
# Networking note: VITE_BACKEND_BASE_URL is left at its .env.example default
# (http://localhost:8000) unmodified - import.meta.env.VITE_* is read by
# browser JS running on the host, so "localhost:8000" correctly resolves to
# the backend-service VM's forwarded port. This guest itself only needs to
# reach backend-service (via its own slirp gateway alias 10.0.2.2) for the
# readiness check below, not for anything the running app does.
set -euo pipefail

APP_DIR="/app"
GATEWAY="10.0.2.2"

export DEBIAN_FRONTEND=noninteractive

echo ">>> Installing Node.js LTS"
apt-get update -y
apt-get install -y curl ca-certificates
if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
  apt-get install -y nodejs
fi

echo ">>> Waiting for backend-service (${GATEWAY}:8000) to respond"
for i in $(seq 1 30); do
  if curl -fsS -o /dev/null "http://${GATEWAY}:8000/docs"; then
    echo "    backend-service is up"
    break
  fi
  echo "    attempt ${i}/30: not ready yet, retrying in 2s"
  sleep 2
done

echo ">>> Setting up ui-service"
cd "${APP_DIR}"
[ -f .env ] || cp .env.example .env
npm install

echo ">>> Installing systemd unit"
cat > /etc/systemd/system/ui-service.service <<'EOF'
[Unit]
Description=SkyIvano UI Service
After=network.target

[Service]
Type=simple
User=vagrant
WorkingDirectory=/app
ExecStart=/usr/bin/npx vite --host 0.0.0.0 --port 5173
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

chown -R vagrant:vagrant "${APP_DIR}/node_modules"
systemctl daemon-reload
systemctl enable --now ui-service

echo ">>> Provisioning complete"
echo "    UI Service reachable at http://localhost:5173"
