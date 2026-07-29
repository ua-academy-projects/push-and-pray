#!/usr/bin/env bash

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

readonly APP_ROOT="/opt/weather-app"

log() {
    printf '\n[weather-app] %s\n' "$*"
}


install_packages() {
    apt-get install -y --no-install-recommends "$@"
}


install_docker() {
    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        log "Docker and Docker Compose are already installed"
        return 0
    fi

    log "Installing Docker Engine and Docker Compose plugin"
    apt-get update
    install_packages ca-certificates curl gnupg lsb-release

    install -m 0755 -d /etc/apt/keyrings
    if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
        chmod a+r /etc/apt/keyrings/docker.asc
    fi

    local arch
    arch="$(dpkg --print-architecture)"
    local codename
    codename="$(lsb_release -cs 2>/dev/null || echo "noble")"

    echo "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${codename} stable" \
        > /etc/apt/sources.list.d/docker.list

    apt-get update
    install_packages docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    systemctl enable --now docker
    usermod -aG docker vagrant || true
}


configure_firewall() {
    if command -v ufw >/dev/null 2>&1 \
        && ufw status | grep -q "Status: active"; then

        log "Configuring firewall for ICMP and private network access"
        ufw allow proto icmp || true
        ufw allow from 192.168.56.0/24 || true
    fi
}


configure_common_system() {
    log "Updating package metadata"
    apt-get update

    log "Installing common system packages"
    install_packages \
        ca-certificates \
        curl

    install -d "${APP_ROOT}"
    configure_firewall
    install_docker
}


if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    configure_common_system
    log "Common provisioning completed"
fi
