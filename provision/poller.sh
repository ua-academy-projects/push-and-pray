#!/usr/bin/env bash
set -euo pipefail

apt-get update -y
apt-get install -y docker.io
systemctl enable --now docker
systemctl disable --now poller.service 2>/dev/null || true

docker build --network host --tag academy-poller:latest /vagrant/app
docker rm --force academy-poller 2>/dev/null || true
docker run --detach \
  --name academy-poller \
  --restart unless-stopped \
  --network host \
  --env PROXY_SERVICE_URL="${PROXY_SERVICE_URL}" \
  --env WATCHED_CITIES=Kyiv,Warsaw,Berlin \
  --env POLL_INTERVAL_SECONDS=900 \
  academy-poller:latest
