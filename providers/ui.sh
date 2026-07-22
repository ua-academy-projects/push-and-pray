#!/usr/bin/env bash

set -euo pipefail

source /vagrant/providers/common.sh

readonly SERVICE_NAME="ui-service"
readonly SYSTEMD_SERVICE="weather-ui.service"

install_python_runtime
sync_python_service "${SERVICE_NAME}"

log "Writing the UI Service systemd unit"

cat > "/etc/systemd/system/${SYSTEMD_SERVICE}" <<'EOF'
[Unit]
Description=Weather UI Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=vagrant
Group=vagrant
WorkingDirectory=/opt/weather-app/ui-service
Environment="APP_HOST=0.0.0.0"
Environment="APP_PORT=5000"
Environment="FLASK_DEBUG=false"
Environment="BACKEND_URL=http://192.168.56.11:5001"
ExecStartPre=/bin/bash -c 'until curl -fsS http://192.168.56.11:5001/health; do echo "Waiting for Backend Service..."; sleep 3; done'
ExecStart=/opt/weather-app/ui-service/venv/bin/python /opt/weather-app/ui-service/app.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

if command -v ufw >/dev/null 2>&1 \
    && ufw status | grep -q "Status: active"; then

    log "Allowing the UI port through the Ubuntu firewall"
    ufw allow 5000/tcp
fi

enable_and_restart_service "${SYSTEMD_SERVICE}"

log "UI Service provisioning completed"
