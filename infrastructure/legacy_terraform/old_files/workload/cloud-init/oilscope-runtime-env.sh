#!/usr/bin/env bash

set -Eeuo pipefail
set +x

# shellcheck disable=SC1091
source /etc/oilscope/role.conf

RUNTIME_ENV=/opt/oilscope/runtime/.env

log() {
  printf '[oilscope-runtime] %s\n' "$*"
}

access_token() {
  curl -fsS \
    -H 'Metadata-Flavor: Google' \
    'http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token' \
    | jq -er '.access_token'
}

read_secret() {
  local secret_id="$1"
  local token=""
  local value=""

  [[ -n "${secret_id}" ]] || return 1
  token="$(access_token)"
  value="$(curl -fsS \
    -H "Authorization: Bearer ${token}" \
    "https://secretmanager.googleapis.com/v1/projects/${PROJECT_ID}/secrets/${secret_id}/versions/latest:access" \
    | jq -er '.payload.data' \
    | base64 --decode)"
  unset token

  if [[ -z "${value}" || "${value}" == *$'\n'* || "${value}" == *$'\r'* ]]; then
    log "Secret ${secret_id} is empty or contains a newline"
    return 1
  fi
  if [[ ! "${value}" =~ ^[A-Za-z0-9._~-]+$ ]]; then
    log "Secret ${secret_id} contains characters unsupported by the current application URLs"
    return 1
  fi
  printf '%s' "${value}"
}

write_env() {
  local file="$1"
  local key="$2"
  local value="$3"

  if [[ ! "${value}" =~ ^[A-Za-z0-9._~%:@/?+=,-]+$ ]]; then
    log "Value for ${key} contains characters unsupported by the runtime env format"
    return 1
  fi
  printf '%s=%s\n' "${key}" "${value}" >> "${file}"
}

configure_ghcr() {
  local username=""
  local token=""

  [[ "${GHCR_REQUIRED}" == "true" ]] || return 0
  username="$(read_secret "${GHCR_USERNAME_SECRET}")"
  token="$(read_secret "${GHCR_READ_TOKEN_SECRET}")"
  install -d -o root -g root -m 0700 "${DOCKER_CONFIG:?DOCKER_CONFIG is required}"
  printf '%s' "${token}" | docker login ghcr.io \
    --username "${username}" \
    --password-stdin >/dev/null
  unset username token
}

main() {
  local temporary=""
  local value=""

  install -d -o root -g root -m 0700 /opt/oilscope/runtime
  temporary="$(mktemp /opt/oilscope/runtime/.env.XXXXXX)"
  chmod 0600 "${temporary}"
  trap 'rm -f "${temporary}"' EXIT

  case "${ROLE}" in
    infra)
      value="$(read_secret "${DB_PASSWORD_SECRET}")"
      write_env "${temporary}" DB_PASSWORD "${value}"
      value="$(read_secret "${RABBITMQ_USERNAME_SECRET}")"
      write_env "${temporary}" RABBITMQ_USER "${value}"
      value="$(read_secret "${RABBITMQ_PASSWORD_SECRET}")"
      write_env "${temporary}" RABBITMQ_PASSWORD "${value}"
      ;;
    history)
      write_env "${temporary}" GHCR_OWNER "${GHCR_OWNER}"
      write_env "${temporary}" HISTORY_IMAGE_TAG "${IMAGE_TAG}"
      value="$(read_secret "${DB_PASSWORD_SECRET}")"
      write_env "${temporary}" DB_PASSWORD "${value}"
      value="$(read_secret "${RABBITMQ_USERNAME_SECRET}")"
      write_env "${temporary}" RABBITMQ_USER "${value}"
      value="$(read_secret "${RABBITMQ_PASSWORD_SECRET}")"
      write_env "${temporary}" RABBITMQ_PASSWORD "${value}"
      ;;
    fetcher)
      write_env "${temporary}" GHCR_OWNER "${GHCR_OWNER}"
      write_env "${temporary}" FETCHER_IMAGE_TAG "${IMAGE_TAG}"
      value="$(read_secret "${DB_PASSWORD_SECRET}")"
      write_env "${temporary}" DB_PASSWORD "${value}"
      value="$(read_secret "${OILPRICEAPI_KEY_SECRET}")"
      write_env "${temporary}" OILPRICEAPI_KEY "${value}"
      ;;
    ui)
      write_env "${temporary}" GHCR_OWNER "${GHCR_OWNER}"
      write_env "${temporary}" UI_IMAGE_TAG "${IMAGE_TAG}"
      write_env "${temporary}" APP_DOMAIN "${APP_DOMAIN}"
      write_env "${temporary}" ACME_EMAIL "${ACME_EMAIL}"
      value="$(read_secret "${DB_PASSWORD_SECRET}")"
      write_env "${temporary}" DB_PASSWORD "${value}"
      ;;
    *)
      log "Unsupported VM role: ${ROLE}"
      return 1
      ;;
  esac

  mv -f "${temporary}" "${RUNTIME_ENV}"
  chmod 0600 "${RUNTIME_ENV}"
  trap - EXIT
  configure_ghcr
  log "Runtime configuration refreshed for role ${ROLE}"
}

main "$@"
