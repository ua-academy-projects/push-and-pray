#!/usr/bin/env bash
# Provisions the ui-service VM: Node.js LTS, npm install, and a systemd unit
# to run the Vite dev server.
#
# Networking note: VITE_BACKEND_BASE_URL is set to the backend-service VM's
# bridged LAN IP, not localhost - import.meta.env.VITE_* is baked into
# browser JS that can run on *any* device on the LAN (not just this host),
# so "localhost:8000" would wrongly resolve to whichever device loaded the
# page. The backend's real LAN IP works from the host and from every other
# device alike. This guest itself also uses that same IP for the readiness
# check below.
set -euo pipefail

APP_DIR="/app"
BACKEND_IP="192.168.0.221"

export DEBIAN_FRONTEND=noninteractive

echo ">>> Installing Node.js LTS"
apt-get update -y
apt-get install -y curl ca-certificates
if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
  apt-get install -y nodejs
fi

echo ">>> Waiting for backend-service (${BACKEND_IP}:8000) to respond"
for i in $(seq 1 30); do
  if curl -fsS -o /dev/null "http://${BACKEND_IP}:8000/docs"; then
    echo "    backend-service is up"
    break
  fi
  echo "    attempt ${i}/30: not ready yet, retrying in 2s"
  sleep 2
done

echo ">>> Setting up ui-service"
cd "${APP_DIR}"
[ -f .env ] || cp .env.example .env
sed -i "s#^VITE_BACKEND_BASE_URL=.*#VITE_BACKEND_BASE_URL=http://${BACKEND_IP}:8000#" .env
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
echo "    UI Service reachable at http://192.168.0.223:5173 from this Mac or any other device on the LAN"
