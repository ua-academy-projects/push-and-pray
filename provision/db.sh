#!/usr/bin/env bash
set -euo pipefail

apt-get update -y
apt-get install -y docker.io docker-compose-v2
systemctl enable --now docker

# Stop services from the pre-container version when an existing VM is reprovisioned.
systemctl disable --now postgresql.service 2>/dev/null || true
systemctl disable --now redis-server.service 2>/dev/null || true
systemctl disable --now rabbitmq-server.service 2>/dev/null || true

cd /vagrant/app
docker compose down --remove-orphans 2>/dev/null || true
docker rm --force academy-postgres academy-redis academy-rabbitmq 2>/dev/null || true
docker compose up --detach --remove-orphans
