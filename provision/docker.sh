#!/usr/bin/env bash
set -Eeuo pipefail

log() {
    printf '\n[%s] %s\n' "$(date --iso-8601=seconds)" "$*"
}

export DEBIAN_FRONTEND=noninteractive

if command -v docker >/dev/null 2>&1 \
    && docker compose version >/dev/null 2>&1; then
    log "Docker Engine and Docker Compose are already installed"
    systemctl enable --now docker
    exit 0
fi

log "Installing Docker Engine and Docker Compose plugin"

apt-get update
apt-get install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

. /etc/os-release
cat >/etc/apt/sources.list.d/docker.sources <<APT_SOURCE
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME:-$VERSION_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
APT_SOURCE

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
log "Docker installation completed"
