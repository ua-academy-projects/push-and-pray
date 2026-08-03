#!/usr/bin/env bash
set -euo pipefail

install -m 0600 -o root -g root /tmp/rateboard.env /etc/rateboard/backend-service.env
rm -f /tmp/rateboard.env

systemctl disable --now rateboard-backend-service.service rateboard-history-service.service 2>/dev/null || true
docker compose \
  --env-file /etc/rateboard/backend-service.env \
  --file /vagrant/infra/docker/backend-service/compose.yml \
  up --detach --build --force-recreate --remove-orphans
