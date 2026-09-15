#!/usr/bin/env bash

set -Eeuo pipefail

# shellcheck source=infrastructure/vagrant/provisioning/lib.sh
source /vagrant/infrastructure/vagrant/provisioning/lib.sh
load_project_config

export DEBIAN_FRONTEND=noninteractive

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  systemctl enable --now docker
  usermod -aG docker vagrant
  log "Docker Engine and Compose plugin are already installed"
  exit 0
fi

for package in docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc; do
  apt-get remove -y "${package}" >/dev/null 2>&1 || true
done

apt-get update
apt-get install -y --no-install-recommends ca-certificates curl

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

architecture="$(dpkg --print-architecture)"
. /etc/os-release
ubuntu_codename="${UBUNTU_CODENAME:-${VERSION_CODENAME}}"

{
  printf '%s\n' 'Types: deb'
  printf '%s\n' 'URIs: https://download.docker.com/linux/ubuntu'
  printf 'Suites: %s\n' "${ubuntu_codename}"
  printf '%s\n' 'Components: stable'
  printf 'Architectures: %s\n' "${architecture}"
  printf '%s\n' 'Signed-By: /etc/apt/keyrings/docker.asc'
} > /etc/apt/sources.list.d/docker.sources

apt-get update
apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

systemctl enable --now docker
usermod -aG docker vagrant

docker version
docker compose version

log "Docker Engine and Compose plugin installed from the official Docker apt repository"
