#!/usr/bin/env bash

set -Eeuo pipefail

HOST_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
VAGRANT_BIN="$(command -v vagrant 2>/dev/null || true)"

load_host_config() {
  local config_file="${HOST_PROJECT_ROOT}/infrastructure/vagrant/config/vagrant.env"
  if [[ ! -f "${config_file}" ]]; then
    printf 'Missing %s. Copy infrastructure/vagrant/config/vagrant.env.example first.\n' "${config_file}" >&2
    return 1
  fi
  set -a
  # shellcheck disable=SC1090
  source "${config_file}"
  set +a
}

repair_vagrant_ownership() {
  [[ "$(uname -s)" == "Darwin" ]] || return 0

  local owner_uid="${SUDO_UID:-$(id -u)}"
  local owner_gid="${SUDO_GID:-$(id -g)}"
  local vagrant_home="${VAGRANT_HOME:-${HOME}/.vagrant.d}"
  local targets=(
    "${HOST_PROJECT_ROOT}/.vagrant"
    "${vagrant_home}/data"
    "${vagrant_home}/tmp/vagrant-qemu"
  )
  local target

  for target in "${targets[@]}"; do
    [[ -e "${target}" ]] || continue
    if [[ -n "$(find "${target}" ! -uid "${owner_uid}" -print -quit 2>/dev/null)" ]]; then
      sudo chown -R "${owner_uid}:${owner_gid}" "${target}"
    fi
  done
}

run_vagrant() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    local user_home="${HOME}"
    local vagrant_home="${VAGRANT_HOME:-${user_home}/.vagrant.d}"
    local command_status=0
    sudo env \
      HOME="${user_home}" \
      VAGRANT_HOME="${vagrant_home}" \
      OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES \
      "${VAGRANT_BIN}" "$@" || command_status=$?
    repair_vagrant_ownership
    return "${command_status}"
  else
    "${VAGRANT_BIN}" "$@"
  fi
}

lan_ip_for() {
  local machine="$1"
  local configured_ip=""
  case "${machine}" in
    database) configured_ip="${DB_LAN_IP:-}" ;;
    history) configured_ip="${HISTORY_LAN_IP:-}" ;;
    fetcher) configured_ip="${FETCHER_LAN_IP:-}" ;;
    ui) configured_ip="${UI_LAN_IP:-}" ;;
  esac

  printf '%s\n' "${configured_ip}"
}

service_url_for() {
  local machine="$1"
  local ip="$2"
  case "${machine}" in
    database) printf 'postgresql://oil_tracker@%s:5432/oil_tracker\n' "${ip}" ;;
    rabbitmq) printf 'http://%s:15672\n' "${ip}" ;;
    history) printf 'http://%s:8001/docs (RabbitMQ management: http://%s:15672)\n' "${ip}" "${ip}" ;;
    fetcher) printf 'http://%s:8002/health\n' "${ip}" ;;
    ui) printf 'http://%s:8080\n' "${ip}" ;;
  esac
}
