#!/usr/bin/env bash

set -euo pipefail

source /vagrant/providers/common.sh

readonly SERVICE_NAME="backend-service"
readonly SYSTEMD_SERVICE="weather-backend.service"

install_python_runtime
install_packages postgresql-client
sync_python_service "${SERVICE_NAME}"

log "Writing the Backend Service systemd unit"

cat > "/etc/systemd/system/${SYSTEMD_SERVICE}" <<'EOF'
[Unit]
Description=Weather Backend Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=vagrant
Group=vagrant
WorkingDirectory=/opt/weather-app/backend-service
Environment="APP_HOST=0.0.0.0"
Environment="APP_PORT=5001"
Environment="FLASK_DEBUG=false"
Environment="DATABASE_URL=postgresql://weather_user:weather_password@192.168.56.13:5432/weather_history"
Environment="PROVIDER_URL=http://192.168.56.12:5002"
ExecStartPre=/bin/bash -c 'until pg_isready -h 192.168.56.13 -p 5432 -U weather_user -d weather_history; do echo "Waiting for PostgreSQL..."; sleep 3; done'
ExecStartPre=/bin/bash -c 'until curl -fsS http://192.168.56.12:5002/health; do echo "Waiting for Provider Service..."; sleep 3; done'
ExecStart=/opt/weather-app/backend-service/venv/bin/python /opt/weather-app/backend-service/app.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

if command -v ufw >/dev/null 2>&1 \
    && ufw status | grep -q "Status: active"; then

    log "Allowing the Backend port through the Ubuntu firewall"
    ufw allow 5001/tcp
fi

enable_and_restart_service "${SYSTEMD_SERVICE}"

log "Backend Service provisioning completed"
