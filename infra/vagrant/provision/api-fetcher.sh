#!/usr/bin/env bash
set -euo pipefail

install -m 0600 -o root -g root /tmp/rateboard.env /etc/rateboard/api-fetcher.env
rm -f /tmp/rateboard.env

systemctl disable --now rateboard-api-fetcher.service rateboard-backend.service 2>/dev/null || true
docker compose \
  --env-file /etc/rateboard/api-fetcher.env \
  --env-file /etc/rateboard/alloy.env \
  --file /vagrant/infra/docker/api-fetcher/compose.yml \
  up --detach --build --force-recreate --remove-orphans
