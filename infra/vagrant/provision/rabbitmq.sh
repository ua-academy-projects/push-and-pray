#!/usr/bin/env bash
set -euo pipefail

install -m 0600 -o root -g root /tmp/rateboard.env /etc/rateboard/rabbitmq.env
rm -f /tmp/rateboard.env

systemctl disable --now rabbitmq-server redis-server 2>/dev/null || true
docker compose \
  --env-file /etc/rateboard/rabbitmq.env \
  --env-file /etc/rateboard/alloy.env \
  --file /vagrant/infra/docker/rabbitmq/compose.yml \
  up --detach --remove-orphans
