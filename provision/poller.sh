#!/usr/bin/env bash
set -euo pipefail

apt-get update -y
apt-get install -y docker.io docker-compose-v2
systemctl enable --now docker
systemctl disable --now poller.service 2>/dev/null || true

cd /vagrant/app
docker compose down --remove-orphans 2>/dev/null || true
docker rm --force academy-poller 2>/dev/null || true
docker compose up --detach --build --remove-orphans
