#!/usr/bin/env bash

set -euo pipefail

source /vagrant/providers/common.sh

readonly SERVICE_NAME="provider-service"
readonly SYSTEMD_SERVICE="weather-provider.service"

install_python_runtime
sync_python_service "${SERVICE_NAME}"

if systemctl list-unit-files \
    | grep -q '^weather-history.service'; then

    log "Removing the legacy History Service unit"
    systemctl disable --now weather-history.service
    rm -f /etc/systemd/system/weather-history.service
fi

log "Writing the Provider Service systemd unit"

cat > "/etc/systemd/system/${SYSTEMD_SERVICE}" <<'EOF'
[Unit]
Description=Weather Provider Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=vagrant
Group=vagrant
WorkingDirectory=/opt/weather-app/provider-service
Environment="APP_HOST=0.0.0.0"
Environment="APP_PORT=5002"
Environment="FLASK_DEBUG=false"
Environment="EXTERNAL_WEATHER_URL=https://api.open-meteo.com/v1/forecast"
ExecStart=/opt/weather-app/provider-service/venv/bin/python /opt/weather-app/provider-service/app.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

enable_and_restart_service "${SYSTEMD_SERVICE}"

log "Provider Service provisioning completed"
