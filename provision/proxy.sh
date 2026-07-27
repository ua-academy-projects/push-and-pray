#!/usr/bin/env bash
set -euo pipefail

apt-get update -y
apt-get install -y docker.io
systemctl enable --now docker
systemctl disable --now proxy.service 2>/dev/null || true

docker build --network host --tag academy-proxy:latest /vagrant/app
docker rm --force academy-proxy 2>/dev/null || true
docker run --detach \
  --name academy-proxy \
  --restart unless-stopped \
  --network host \
  --env RABBITMQ_URL="${RABBITMQ_URL}" \
  --env PORT=5001 \
  --health-cmd="python -c \"import urllib.request; urllib.request.urlopen('http://localhost:5001/health')\"" \
  --health-interval=5s \
  --health-timeout=3s \
  --health-retries=12 \
  --health-start-period=10s \
  academy-proxy:latest
