#!/usr/bin/env bash
set -euo pipefail

apt-get update -y
apt-get install -y python3 python3-venv python3-pip

python3 -m venv /opt/venv
/opt/venv/bin/pip install --no-cache-dir -r /vagrant/app/requirements.txt

cat > /etc/systemd/system/ui.service <<EOF
[Unit]
Description=ui-service
After=network.target

[Service]
Type=simple
WorkingDirectory=/vagrant/app

Environment=PROXY_SERVICE_URL=${PROXY_SERVICE_URL}
Environment=REDIS_HOST=${REDIS_HOST}
Environment=PORT=5000

ExecStart=/opt/venv/bin/python /vagrant/app/ui.py

Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ui.service
systemctl restart ui.service
