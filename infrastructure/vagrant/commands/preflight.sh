#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=infrastructure/vagrant/commands/host-lib.sh
source "${SCRIPT_DIR}/host-lib.sh"
load_host_config
cd "${HOST_PROJECT_ROOT}"
repair_vagrant_ownership

if [[ -z "${VAGRANT_BIN}" ]]; then
  printf 'Vagrant is not installed or is not in PATH.\n' >&2
  exit 1
fi

required_credentials=(DB_PASSWORD REDIS_PASSWORD RABBITMQ_USER RABBITMQ_PASSWORD)
for variable in "${required_credentials[@]}"; do
  if [[ -z "${!variable:-}" ]]; then
    printf '%s must be set in infrastructure/vagrant/config/vagrant.env.\n' "${variable}" >&2
    exit 1
  fi
done

: "${SSH_ADMIN_USER:?SSH_ADMIN_USER must be set in infrastructure/vagrant/config/vagrant.env}"
: "${SSH_PRIVATE_KEY_PATH:?SSH_PRIVATE_KEY_PATH must be set in infrastructure/vagrant/config/vagrant.env}"
if [[ ! "${SSH_ADMIN_USER}" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
  printf 'SSH_ADMIN_USER must be a valid Linux username.\n' >&2
  exit 1
fi
ssh_identity="${SSH_PRIVATE_KEY_PATH}"
if [[ "${ssh_identity}" == "~/"* ]]; then
  ssh_identity="${HOME}/${ssh_identity#\~/}"
fi
if [[ ! -f "${ssh_identity}" || ! -f "${ssh_identity}.pub" ]]; then
  printf 'SSH identity is missing. Run ./infrastructure/vagrant/commands/ssh-setup.sh first.\n' >&2
  exit 1
fi
if ! ssh-keygen -l -f "${ssh_identity}.pub" >/dev/null 2>&1; then
  printf 'Invalid SSH public key: %s.pub\n' "${ssh_identity}" >&2
  exit 1
fi

if [[ "${DB_PASSWORD:-}" == "change-me" || "${REDIS_PASSWORD:-}" == "change-me" || "${RABBITMQ_PASSWORD:-}" == "change-me" ]]; then
  printf 'Replace all change-me passwords in infrastructure/vagrant/config/vagrant.env before deployment.\n' >&2
  exit 1
fi

machines=(
  "database:${DB_LAN_IP:-}"
  "history:${HISTORY_LAN_IP:-}"
  "fetcher:${FETCHER_LAN_IP:-}"
  "ui:${UI_LAN_IP:-}"
)
required_ips=()
for entry in "${machines[@]}"; do
  ip="${entry#*:}"
  if [[ -z "${ip}" ]]; then
    printf 'All four *_LAN_IP values must be set in infrastructure/vagrant/config/vagrant.env.\n' >&2
    exit 1
  fi
  required_ips+=("${ip}")
done

if ! vagrant plugin list | grep -q '^vagrant-qemu '; then
  printf 'Missing vagrant-qemu plugin. Install it with: vagrant plugin install vagrant-qemu\n' >&2
  exit 1
fi
if [[ "$(uname -s)" == "Darwin" && -z "${QEMU_VMNET_INTERFACE:-}" ]]; then
  printf 'QEMU_VMNET_INTERFACE is required for vmnet-bridged networking.\n' >&2
  exit 1
fi

for entry in "${machines[@]}"; do
  machine="${entry%%:*}"
  ip="${entry#*:}"
  if [[ -f ".vagrant/machines/${machine}/qemu/id" ]]; then
    continue
  fi
  if ping -c 1 -W 500 "${ip}" >/dev/null 2>&1; then
    printf 'LAN IP %s already responds. Choose an unused/reserved address.\n' "${ip}" >&2
    exit 1
  fi
done

printf 'Preflight passed: provider=%s, LAN=%s, addresses=%s\n' \
  "qemu" \
  "${LAN_CIDR}" \
  "${required_ips[*]}"
