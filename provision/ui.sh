#!/usr/bin/env bash
set -euo pipefail

apt-get update -y
apt-get install -y docker.io
systemctl enable --now docker
systemctl disable --now ui.service 2>/dev/null || true

docker build --network host --tag academy-ui:latest /vagrant/app
docker rm --force academy-ui 2>/dev/null || true
docker run --detach \
  --name academy-ui \
  --restart unless-stopped \
  --network host \
  --env BACKEND_SERVICE_URL="${BACKEND_SERVICE_URL}" \
  --env REDIS_HOST="${REDIS_HOST}" \
  --env REDIS_PORT=6379 \
  --env PORT=5000 \
  --health-cmd="python -c \"import urllib.request; urllib.request.urlopen('http://localhost:5000/health')\"" \
  --health-interval=5s \
  --health-timeout=3s \
  --health-retries=12 \
  --health-start-period=10s \
  academy-ui:latest
