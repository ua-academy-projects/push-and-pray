#!/usr/bin/env bash
set -euo pipefail

apt-get update -y
apt-get install -y docker.io
systemctl enable --now docker
systemctl disable --now backend.service 2>/dev/null || true

docker build --network host --tag academy-backend:latest /vagrant/app
docker rm --force academy-backend 2>/dev/null || true
docker run --detach \
  --name academy-backend \
  --restart unless-stopped \
  --network host \
  --env DB_HOST="${DB_HOST}" \
  --env DB_PORT=5432 \
  --env DB_NAME="${DB_NAME}" \
  --env DB_USER="${DB_USER}" \
  --env DB_PASSWORD="${DB_PASSWORD}" \
  --env RABBITMQ_URL="${RABBITMQ_URL}" \
  --env PORT=5002 \
  --health-cmd="python -c \"import urllib.request; urllib.request.urlopen('http://localhost:5002/health')\"" \
  --health-interval=5s \
  --health-timeout=3s \
  --health-retries=12 \
  --health-start-period=10s \
  academy-backend:latest
