#!/usr/bin/env bash
set -euo pipefail

: "${LOG_SERVER_URL:?LOG_SERVER_URL is required}"

apt-get update -y
apt-get install -y systemd-journal-remote

install -d -m 755 /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/academy-persistent.conf <<'EOF'
[Journal]
Storage=persistent
SystemMaxUse=500M
EOF

install -d -m 755 /var/log/journal
systemd-tmpfiles --create --prefix /var/log/journal
systemctl restart systemd-journald

install -d -m 755 /etc/systemd/journal-upload.conf.d
cat > /etc/systemd/journal-upload.conf.d/academy.conf <<EOF
[Upload]
URL=${LOG_SERVER_URL}
EOF

install -d -m 755 /etc/systemd/system/systemd-journal-upload.service.d
cat > /etc/systemd/system/systemd-journal-upload.service.d/restart.conf <<'EOF'
[Service]
Restart=always
RestartSec=5s
EOF

systemctl daemon-reload
systemctl enable --now systemd-journal-upload.service
