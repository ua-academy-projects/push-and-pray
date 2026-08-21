#!/usr/bin/env bash

set -Eeuo pipefail

required_environment=(
  DB_PASSWORD
  OILPRICEAPI_KEY
  DB_PASSWORD_SECRET_ID
  OILPRICEAPI_KEY_SECRET_ID
)

for variable in "${required_environment[@]}"; do
  if [[ -z "${!variable:-}" ]]; then
    printf '%s must be set in the current process environment.\n' "${variable}" >&2
    exit 1
  fi
done

if [[ -n "${GHCR_USERNAME_SECRET_ID:-}" || -n "${GHCR_TOKEN_SECRET_ID:-}" ]]; then
  if [[ -z "${GHCR_USERNAME_SECRET_ID:-}" || -z "${GHCR_TOKEN_SECRET_ID:-}" ]]; then
    printf 'GHCR_USERNAME_SECRET_ID and GHCR_TOKEN_SECRET_ID must be provided together.\n' >&2
    exit 1
  fi
  if [[ -z "${GHCR_USERNAME:-}" || -z "${GHCR_TOKEN:-}" ]]; then
    printf 'GHCR_USERNAME and GHCR_TOKEN must be set when GHCR secret IDs are configured.\n' >&2
    exit 1
  fi
fi

if ! command -v gcloud >/dev/null 2>&1; then
  printf 'gcloud is required to publish Secret Manager versions.\n' >&2
  exit 1
fi

publish_secret() {
  local secret_id="$1"
  local secret_value="$2"

  if ! printf '%s' "${secret_value}" |
    gcloud secrets versions add "${secret_id}" --data-file=- --quiet >/dev/null 2>&1; then
    printf 'Failed to publish a Secret Manager version for %s.\n' "${secret_id}" >&2
    return 1
  fi
}

publish_secret "${DB_PASSWORD_SECRET_ID}" "${DB_PASSWORD}"
publish_secret "${OILPRICEAPI_KEY_SECRET_ID}" "${OILPRICEAPI_KEY}"

if [[ -n "${GHCR_USERNAME_SECRET_ID:-}" ]]; then
  publish_secret "${GHCR_USERNAME_SECRET_ID}" "${GHCR_USERNAME}"
  publish_secret "${GHCR_TOKEN_SECRET_ID}" "${GHCR_TOKEN}"
fi

printf 'Secret Manager versions published successfully.\n'