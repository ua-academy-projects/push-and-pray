#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get -o DPkg::Lock::Timeout=300 update -qq
apt-get -o DPkg::Lock::Timeout=300 install -y --no-install-recommends openssl

# shellcheck disable=SC1091
source /tmp/rateboard.env
install -m 0600 -o root -g root /tmp/rateboard.env /etc/rateboard/ui.env
rm -f /tmp/rateboard.env
printf 'window.RATEBOARD_CONFIG = { HISTORY_API_BASE_URL: "/api/v1" };\n' \
  > /etc/rateboard/runtime-config.js

install -d -m 0700 /etc/rateboard/tls
if [[ ! -f /etc/rateboard/tls/ui.key || ! -f /etc/rateboard/tls/ui.crt ]]; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 825 \
    -keyout /etc/rateboard/tls/ui.key \
    -out /etc/rateboard/tls/ui.crt \
    -subj "/CN=${UI_PUBLIC_HOST}" \
    -addext "subjectAltName=DNS:${UI_PUBLIC_HOST},IP:${UI_PUBLIC_IP}" \
    >/dev/null 2>&1
fi
chmod 0600 /etc/rateboard/tls/ui.key
chmod 0644 /etc/rateboard/tls/ui.crt

systemctl disable --now nginx rateboard-ui.service 2>/dev/null || true
docker compose \
  --env-file /etc/rateboard/ui.env \
  --file /vagrant/infra/docker/ui/compose.yml \
  up --detach --build --force-recreate --remove-orphans
