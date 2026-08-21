#!/usr/bin/env bash

set -Eeuo pipefail

usage() {
  printf 'Usage: %s --project-id PROJECT --binding ENV_NAME=SECRET_ID... -- COMMAND [ARG...]\n' "$0" >&2
  exit 2
}

project_id=""
bindings=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-id)
      [[ $# -ge 2 ]] || usage
      project_id="$2"
      shift 2
      ;;
    --binding)
      [[ $# -ge 2 ]] || usage
      bindings+=("$2")
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      usage
      ;;
  esac
done

[[ -n "${project_id}" && ${#bindings[@]} -gt 0 && $# -gt 0 ]] || usage

export COMPOSE_DISABLE_ENV_FILE=1

metadata_token() {
  curl -fsS -H 'Metadata-Flavor: Google' \
    http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token |
    jq -er .access_token
}

token="$(metadata_token)"
access_secret() {
  local secret_id="$1"
  curl -fsS \
    -H "Authorization: Bearer ${token}" \
    "https://secretmanager.googleapis.com/v1/projects/${project_id}/secrets/${secret_id}/versions/latest:access" |
    jq -er .payload.data |
    base64 -d
}

runtime_dir="$(mktemp -d /run/oil-price-tracker-secrets.XXXXXX)"
chmod 0700 "${runtime_dir}"
trap 'rm -rf "${runtime_dir}"' EXIT
export DOCKER_CONFIG="${runtime_dir}/docker"
mkdir -m 0700 "${DOCKER_CONFIG}"

for binding in "${bindings[@]}"; do
  [[ "${binding}" == *=* ]] || usage
  environment_name="${binding%%=*}"
  secret_id="${binding#*=}"
  [[ "${environment_name}" =~ ^[A-Z][A-Z0-9_]*$ ]] || usage
  [[ "${secret_id}" =~ ^[A-Za-z0-9_-]+$ ]] || usage
  secret_value="$(access_secret "${secret_id}")"
  export "${environment_name}=${secret_value}"
done

"$@"
status=$?
trap - EXIT
rm -rf "${runtime_dir}"
exit "${status}"
