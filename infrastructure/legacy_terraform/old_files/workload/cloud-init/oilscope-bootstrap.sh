#!/usr/bin/env bash

set -Eeuo pipefail

# shellcheck disable=SC1091
source /etc/oilscope/role.conf

log() {
  printf '[oilscope-bootstrap] %s\n' "$*"
}

configure_swap() {
  if [[ ! -f /swapfile ]]; then
    log "Creating 1 GiB swap file"
    if ! fallocate -l 1G /swapfile; then
      dd if=/dev/zero of=/swapfile bs=1M count=1024 status=none
    fi
    chmod 0600 /swapfile
    mkswap /swapfile >/dev/null
  fi

  if ! grep -Eq '^/swapfile[[:space:]]+none[[:space:]]+swap([[:space:]]|$)' /etc/fstab; then
    printf '/swapfile none swap sw 0 0\n' >> /etc/fstab
  fi

  if ! swapon --show=NAME --noheadings | grep -Fxq /swapfile; then
    swapon /swapfile
  fi
}

install_docker() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends ca-certificates curl gnupg jq

  install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
  fi

  # shellcheck disable=SC1091
  source /etc/os-release
  printf '%s\n' \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update
  apt-get install -y --no-install-recommends \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

  systemctl enable --now docker.service
}

prepare_infra_disk() {
  local device="/dev/disk/by-id/google-${INFRA_DATA_DEVICE_NAME}"
  local filesystem=""
  local uuid=""

  for _ in {1..60}; do
    [[ -b "${device}" ]] && break
    sleep 2
  done
  if [[ ! -b "${device}" ]]; then
    log "Persistent disk ${device} was not found"
    return 1
  fi

  filesystem="$(blkid -o value -s TYPE "${device}" 2>/dev/null || true)"
  if [[ -z "${filesystem}" ]]; then
    log "Formatting previously unformatted Infra data disk"
    mkfs.ext4 -F -L oilscope-data "${device}"
    filesystem="ext4"
  fi
  if [[ "${filesystem}" != "ext4" ]]; then
    log "Unsupported existing filesystem on Infra data disk: ${filesystem}"
    return 1
  fi

  uuid="$(blkid -o value -s UUID "${device}")"
  install -d -o root -g root -m 0755 /opt/oilscope/data
  if ! grep -Fq "UUID=${uuid} " /etc/fstab; then
    printf 'UUID=%s /opt/oilscope/data ext4 defaults,nofail 0 2\n' "${uuid}" >> /etc/fstab
  fi
  if ! mountpoint -q /opt/oilscope/data; then
    mount /opt/oilscope/data
  fi

  install -d -o 999 -g 999 -m 0750 \
    /opt/oilscope/data/postgres \
    /opt/oilscope/data/rabbitmq
}

prepare_directories() {
  install -d -o root -g root -m 0755 \
    /etc/oilscope \
    /opt/oilscope \
    /opt/oilscope/deployment \
    /opt/oilscope/runtime
  chmod 0700 /opt/oilscope/runtime

  if [[ "${ROLE}" == "infra" ]]; then
    prepare_infra_disk
  elif [[ "${ROLE}" == "ui" ]]; then
    install -d -o root -g root -m 0700 /opt/oilscope/data/traefik
    touch /opt/oilscope/data/traefik/acme.json
    chmod 0600 /opt/oilscope/data/traefik/acme.json
  fi
}

main() {
  configure_swap
  install_docker
  prepare_directories
  systemctl daemon-reload
  systemctl enable --now oilscope-deployment.service
  log "Provisioning completed for role ${ROLE}"
}

main "$@"
