#!/usr/bin/env bash
set -euo pipefail

apt-get update -y
apt-get install -y docker.io
systemctl enable --now docker

# Stop services from the pre-container version when an existing VM is reprovisioned.
systemctl disable --now postgresql.service 2>/dev/null || true
systemctl disable --now redis-server.service 2>/dev/null || true
systemctl disable --now rabbitmq-server.service 2>/dev/null || true

docker volume create academy-postgres-data
docker volume create academy-redis-data
docker volume create academy-rabbitmq-data

docker rm --force academy-postgres academy-redis academy-rabbitmq 2>/dev/null || true

docker run --detach \
  --name academy-postgres \
  --restart unless-stopped \
  --network host \
  --env POSTGRES_DB="${DB_NAME}" \
  --env POSTGRES_USER="${DB_USER}" \
  --env POSTGRES_PASSWORD="${DB_PASSWORD}" \
  --mount source=academy-postgres-data,target=/var/lib/postgresql/data \
  --health-cmd="pg_isready -U ${DB_USER} -d ${DB_NAME}" \
  --health-interval=5s \
  --health-timeout=5s \
  --health-retries=12 \
  postgres:15-alpine

docker run --detach \
  --name academy-redis \
  --restart unless-stopped \
  --network host \
  --mount source=academy-redis-data,target=/data \
  --health-cmd="redis-cli ping" \
  --health-interval=5s \
  --health-timeout=3s \
  --health-retries=12 \
  redis:7-alpine \
  redis-server --appendonly yes --protected-mode no

docker run --detach \
  --name academy-rabbitmq \
  --restart unless-stopped \
  --network host \
  --env RABBITMQ_DEFAULT_USER=admin \
  --env RABBITMQ_DEFAULT_PASS=admin \
  --mount source=academy-rabbitmq-data,target=/var/lib/rabbitmq \
  --health-cmd="rabbitmq-diagnostics -q ping" \
  --health-interval=5s \
  --health-timeout=5s \
  --health-retries=12 \
  rabbitmq:3.13-management-alpine
