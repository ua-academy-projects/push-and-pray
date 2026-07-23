#!/usr/bin/env bash
set -euo pipefail

apt-get update -y
apt-get install -y python3 python3-venv python3-pip

python3 -m venv /opt/venv
/opt/venv/bin/pip install --no-cache-dir -r /vagrant/app/requirements.txt

cat > /etc/systemd/system/poller.service << EOF
[Unit]
Description=poller-service
After=network.target

[Service]
Type=simple
WorkingDirectory=/vagrant/app
Environment=PROXY_SERVICE_URL=http://${PROXY_IP}:5001
Environment=WATCHED_CITIES=Kyiv,Warsaw,Berlin
Environment=POLL_INTERVAL_SECONDS=900
ExecStart=/opt/venv/bin/python /vagrant/app/poller.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable poller.service
systemctl restart poller.service
