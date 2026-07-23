#!/usr/bin/env bash
set -euo pipefail

apt-get update -y
apt-get install -y python3 python3-venv python3-pip

python3 -m venv /opt/venv
/opt/venv/bin/pip install --no-cache-dir -r /vagrant/app/requirements.txt

cat > /etc/systemd/system/proxy.service << EOF
[Unit]
Description=proxy-service
After=network.target

[Service]
Type=simple
WorkingDirectory=/vagrant/app
Environment=BACKEND_SERVICE_URL=http://${BACKEND_IP}:5002
Environment=PORT=5001
ExecStart=/opt/venv/bin/python /vagrant/app/proxy.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable proxy.service
systemctl restart proxy.service
