#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_SHARE="/vagrant"
DEPLOY_CONFIG="${PROJECT_SHARE}/infrastructure/vagrant/config/vagrant.env"
LOCAL_APP_ENV="/tmp/oil-price-tracker-host.env"
APP_ROOT="/opt/oil-price-tracker"
DOCKER_PROJECT_ROOT="${APP_ROOT}/source"
CONFIG_ROOT="/etc/oil-price-tracker"
COMPOSE_ENV="${CONFIG_ROOT}/docker.env"

log() {
  printf '[oil-price-tracker] %s\n' "$*"
}

load_project_config() {
  if [[ ! -f "${DEPLOY_CONFIG}" ]]; then
    log "Missing ${DEPLOY_CONFIG}. Copy infrastructure/vagrant/config/vagrant.env.example first."
    exit 1
  fi

  set -a
  # shellcheck disable=SC1090
  source "${DEPLOY_CONFIG}"
  if [[ -f "${LOCAL_APP_ENV}" ]]; then
    # shellcheck disable=SC1090
    source "${LOCAL_APP_ENV}"
  fi
  set +a

  : "${DB_PASSWORD:?DB_PASSWORD is required in infrastructure/vagrant/config/vagrant.env}"
  : "${RABBITMQ_USER:?RABBITMQ_USER is required in infrastructure/vagrant/config/vagrant.env}"
  : "${RABBITMQ_PASSWORD:?RABBITMQ_PASSWORD is required in infrastructure/vagrant/config/vagrant.env}"
  : "${DB_LAN_IP:?DB_LAN_IP is required in infrastructure/vagrant/config/vagrant.env}"
  : "${HISTORY_LAN_IP:?HISTORY_LAN_IP is required in infrastructure/vagrant/config/vagrant.env}"
  : "${FETCHER_LAN_IP:?FETCHER_LAN_IP is required in infrastructure/vagrant/config/vagrant.env}"
  : "${UI_LAN_IP:?UI_LAN_IP is required in infrastructure/vagrant/config/vagrant.env}"

  if [[ "${DB_PASSWORD}" == "change-me" || "${RABBITMQ_PASSWORD}" == "change-me" ]]; then
    log "Replace all default passwords in infrastructure/vagrant/config/vagrant.env"
    exit 1
  fi

  local credential
  for credential in "${DB_PASSWORD}" "${RABBITMQ_PASSWORD}" "${RABBITMQ_USER}"; do
    if [[ ! "${credential}" =~ ^[A-Za-z0-9._~-]+$ ]]; then
      log "Credentials must contain only URL-safe characters: A-Z a-z 0-9 . _ ~ -"
      exit 1
    fi
  done

  if [[ -n "${LAN_CIDR:-}" && ! "${LAN_CIDR}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$ ]]; then
    log "LAN_CIDR must use IPv4 CIDR notation, for example 192.168.88.0/24"
    exit 1
  fi
}

service_ip() {
  case "$1" in
    database) printf '%s\n' "${DB_LAN_IP}" ;;
    rabbitmq) printf '%s\n' "${HISTORY_LAN_IP}" ;;
    history) printf '%s\n' "${HISTORY_LAN_IP}" ;;
    fetcher) printf '%s\n' "${FETCHER_LAN_IP}" ;;
    ui) printf '%s\n' "${UI_LAN_IP}" ;;
    *)
      log "Unknown service name: $1"
      return 2
      ;;
  esac
}

sync_docker_project() {
  install -d -o root -g root -m 0755 "${DOCKER_PROJECT_ROOT}"
  rsync -a --delete \
    --exclude '.env' \
    --exclude '.git/' \
    --exclude '.vagrant/' \
    --exclude '.venv/' \
    --exclude '.pytest_cache/' \
    --exclude '.ruff_cache/' \
    --exclude '**/__pycache__/' \
    --exclude '**/node_modules/' \
    --exclude 'infrastructure/vagrant/config/vagrant.env' \
    "${PROJECT_SHARE}/" "${DOCKER_PROJECT_ROOT}/"
}

write_compose_env() {
  local include_api_key="${1:-false}"

  install -d -o root -g root -m 0700 "${CONFIG_ROOT}"
  {
    printf 'DB_LAN_IP=%s\n' "${DB_LAN_IP}"
    printf 'HISTORY_LAN_IP=%s\n' "${HISTORY_LAN_IP}"
    printf 'FETCHER_LAN_IP=%s\n' "${FETCHER_LAN_IP}"
    printf 'UI_LAN_IP=%s\n' "${UI_LAN_IP}"
    printf 'DB_PASSWORD=%s\n' "${DB_PASSWORD}"
    printf 'RABBITMQ_USER=%s\n' "${RABBITMQ_USER}"
    printf 'RABBITMQ_PASSWORD=%s\n' "${RABBITMQ_PASSWORD}"
    printf 'POSTGRES_IMAGE=%s\n' "${POSTGRES_IMAGE:-postgres:18.4-bookworm}"
    printf 'RABBITMQ_IMAGE=%s\n' "${RABBITMQ_IMAGE:-rabbitmq:4.3.4-management}"
    printf 'PYTHON_IMAGE=%s\n' "${PYTHON_IMAGE:-python:3.12.13-slim-bookworm}"
    printf 'UV_IMAGE=%s\n' "${UV_IMAGE:-ghcr.io/astral-sh/uv:0.11.32}"
    printf 'GO_IMAGE=%s\n' "${GO_IMAGE:-golang:1.25-bookworm}"
    printf 'GO_RUNTIME_IMAGE=%s\n' "${GO_RUNTIME_IMAGE:-debian:bookworm-slim}"
    printf 'NODE_IMAGE=%s\n' "${NODE_IMAGE:-node:24.13.0-bookworm-slim}"
    if [[ "${include_api_key}" == "true" ]]; then
      : "${OILPRICEAPI_KEY:?OILPRICEAPI_KEY is required in the project root .env}"
      if [[ "${OILPRICEAPI_KEY}" == "replace-me" ]]; then
        log "Replace OILPRICEAPI_KEY in the project root .env"
        return 1
      fi
      printf 'OILPRICEAPI_KEY=%s\n' "${OILPRICEAPI_KEY}"
    fi
  } > "${COMPOSE_ENV}"
  chmod 0600 "${COMPOSE_ENV}"
}

compose_file_for() {
  printf '%s/infrastructure/docker/compose.%s.yaml\n' "${DOCKER_PROJECT_ROOT}" "$1"
}

compose_project_for() {
  printf 'petroscope-%s\n' "$1"
}

docker_compose() {
  local role="$1"
  shift
  docker compose \
    --env-file "${COMPOSE_ENV}" \
    --file "$(compose_file_for "${role}")" \
    --project-name "$(compose_project_for "${role}")" \
    "$@"
}

disable_native_units() {
  local unit
  for unit in "$@"; do
    if systemctl list-unit-files "${unit}" >/dev/null 2>&1; then
      systemctl disable --now "${unit}" >/dev/null 2>&1 || true
    fi
  done
}

allow_port_if_firewall_active() {
  local port="$1"
  if command -v ufw >/dev/null 2>&1 && ufw status | grep -q '^Status: active'; then
    ufw allow "${port}/tcp"
  fi
}

wait_for_http() {
  local url="$1"
  local label="$2"
  local attempts="${3:-60}"

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if curl -fsS --max-time 3 "${url}" >/dev/null; then
      log "${label} is healthy"
      return 0
    fi
    sleep 2
  done

  log "${label} did not become healthy"
  return 1
}

wait_for_compose_health() {
  local role="$1"
  local service="$2"
  local attempts="${3:-60}"
  local container_id=""
  local health=""
  local state=""

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    container_id="$(docker_compose "${role}" ps --quiet "${service}" 2>/dev/null || true)"
    if [[ -n "${container_id}" ]]; then
      state="$(docker inspect --format '{{.State.Status}}' "${container_id}")"
      health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${container_id}")"
      if [[ "${state}" == "running" && ("${health}" == "healthy" || "${health}" == "none") ]]; then
        log "${service} container is ${state}/${health}"
        return 0
      fi
    fi
    sleep 2
  done

  log "${service} container did not become healthy"
  docker_compose "${role}" ps || true
  docker_compose "${role}" logs --tail=100 "${service}" || true
  return 1
}
