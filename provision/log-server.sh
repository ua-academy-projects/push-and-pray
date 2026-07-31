#!/usr/bin/env bash
set -euo pipefail

apt-get update -y
apt-get install -y systemd-journal-remote

install -d -m 2755 \
  -o systemd-journal-remote \
  -g systemd-journal-remote \
  /var/log/journal/remote

install -d -m 755 /etc/systemd/journal-remote.conf.d
cat > /etc/systemd/journal-remote.conf.d/academy.conf <<'EOF'
[Remote]
SplitMode=host
EOF

install -d -m 755 /etc/systemd/system/systemd-journal-remote.service.d
cat > /etc/systemd/system/systemd-journal-remote.service.d/override.conf <<'EOF'
[Service]
ExecStart=
ExecStart=/lib/systemd/systemd-journal-remote --listen-http=-3 --output=/var/log/journal/remote/
EOF

systemctl daemon-reload
systemctl enable --now systemd-journal-remote.socket
