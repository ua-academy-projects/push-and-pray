#!/usr/bin/env bash
set -euo pipefail

apt-get update -y
apt-get install -y python3 python3-venv python3-pip

python3 -m venv /opt/venv
/opt/venv/bin/pip install --no-cache-dir -r /vagrant/app/requirements.txt

cat > /etc/systemd/system/history-consumer.service << EOF
[Unit]
Description=history-consumer
After=network.target

[Service]
Type=simple
WorkingDirectory=/vagrant/app
Environment=DB_HOST=${DB_HOST}
Environment=DB_PORT=5432
Environment=DB_NAME=${DB_NAME}
Environment=DB_USER=${DB_USER}
Environment=DB_PASSWORD=${DB_PASSWORD}
Environment=RABBITMQ_URL=${RABBITMQ_URL}
ExecStart=/opt/venv/bin/python /vagrant/app/consumer.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable history-consumer.service
systemctl restart history-consumer.service
