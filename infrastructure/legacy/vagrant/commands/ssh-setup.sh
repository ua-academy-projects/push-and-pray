#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=infrastructure/vagrant/commands/host-lib.sh
source "${SCRIPT_DIR}/host-lib.sh"
load_host_config

: "${SSH_ADMIN_USER:?SSH_ADMIN_USER is required in infrastructure/vagrant/config/vagrant.env}"
: "${SSH_PRIVATE_KEY_PATH:?SSH_PRIVATE_KEY_PATH is required in infrastructure/vagrant/config/vagrant.env}"

if [[ ! "${SSH_ADMIN_USER}" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
  printf 'SSH_ADMIN_USER must be a valid Linux username.\n' >&2
  exit 1
fi

expand_home_path() {
  local value="$1"
  if [[ "${value}" == "~/"* ]]; then
    printf '%s/%s\n' "${HOME}" "${value#\~/}"
  else
    printf '%s\n' "${value}"
  fi
}

identity_file="$(expand_home_path "${SSH_PRIVATE_KEY_PATH}")"
public_key="${identity_file}.pub"
ssh_directory="${HOME}/.ssh"
ssh_config="${ssh_directory}/config"
begin_marker="# oil-price-tracker aliases begin"
end_marker="# oil-price-tracker aliases end"

install -d -m 0700 "${ssh_directory}"

if [[ ! -f "${identity_file}" ]]; then
  if [[ -f "${public_key}" ]]; then
    printf 'Public key exists but private key is missing: %s\n' "${identity_file}" >&2
    exit 1
  fi
  ssh-keygen \
    -q \
    -t ed25519 \
    -N '' \
    -C 'oil-price-tracker-admin' \
    -f "${identity_file}"
  printf 'Created project SSH key: %s\n' "${identity_file}"
elif [[ ! -f "${public_key}" ]]; then
  ssh-keygen -y -f "${identity_file}" > "${public_key}"
  chmod 0644 "${public_key}"
fi

chmod 0600 "${identity_file}"
chmod 0644 "${public_key}"

temporary_config="$(mktemp)"
trap 'rm -f "${temporary_config}"' EXIT

if [[ -f "${ssh_config}" ]]; then
  awk \
    -v begin="${begin_marker}" \
    -v end="${end_marker}" \
    '$0 == begin { managed=1; next }
     $0 == end { managed=0; next }
     !managed { print }' \
    "${ssh_config}" > "${temporary_config}"
fi

{
  printf '%s\n' "${begin_marker}"
  printf 'Host app oil-ui\n'
  printf '  HostName %s\n' "${UI_LAN_IP}"
  printf '  User %s\n' "${SSH_ADMIN_USER}"
  printf '  IdentityFile %s\n' "${identity_file}"
  printf '  IdentitiesOnly yes\n'
  printf '  StrictHostKeyChecking accept-new\n\n'

  printf 'Host database oil-database\n'
  printf '  HostName %s\n' "${DB_LAN_IP}"
  printf '  User %s\n' "${SSH_ADMIN_USER}"
  printf '  IdentityFile %s\n' "${identity_file}"
  printf '  IdentitiesOnly yes\n'
  printf '  StrictHostKeyChecking accept-new\n\n'

  printf 'Host history oil-history\n'
  printf '  HostName %s\n' "${HISTORY_LAN_IP}"
  printf '  User %s\n' "${SSH_ADMIN_USER}"
  printf '  IdentityFile %s\n' "${identity_file}"
  printf '  IdentitiesOnly yes\n'
  printf '  StrictHostKeyChecking accept-new\n\n'

  printf 'Host worker fetcher oil-fetcher\n'
  printf '  HostName %s\n' "${FETCHER_LAN_IP}"
  printf '  User %s\n' "${SSH_ADMIN_USER}"
  printf '  IdentityFile %s\n' "${identity_file}"
  printf '  IdentitiesOnly yes\n'
  printf '  StrictHostKeyChecking accept-new\n'
  printf '%s\n' "${end_marker}"
  if [[ -s "${temporary_config}" ]]; then
    printf '\n'
    cat "${temporary_config}"
  fi
} > "${temporary_config}.new"

install -m 0600 "${temporary_config}.new" "${ssh_config}"
rm -f "${temporary_config}.new"

printf 'SSH aliases configured: app, database, history, worker.\n'
