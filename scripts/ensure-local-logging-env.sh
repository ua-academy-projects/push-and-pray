#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_file="${root_dir}/.env.vagrant.local"

[[ -f "${env_file}" ]] || { echo "Missing ${env_file}" >&2; exit 1; }
command -v openssl >/dev/null 2>&1 || { echo "openssl is required" >&2; exit 1; }

has_value() {
  local name="$1"
  awk -F= -v key="${name}" '
    $1 == key {
      sub(/^[^=]*=/, "")
      if (length($0) > 0 && $0 !~ /^replace-with-/) found = 1
    }
    END { exit !found }
  ' "${env_file}"
}

append_generated_value() {
  local name="$1"
  local generated_value temporary_env
  if ! has_value "${name}"; then
    generated_value="$(openssl rand -hex 24)"
    if grep -q "^${name}=" "${env_file}"; then
      temporary_env="$(mktemp)"
      awk -F= -v key="${name}" -v value="${generated_value}" \
        '$1 == key {print key "=" value; next} {print}' "${env_file}" > "${temporary_env}"
      cp "${temporary_env}" "${env_file}"
      chmod 0600 "${env_file}"
      rm -f "${temporary_env}"
    else
      printf '%s=%s\n' "${name}" "${generated_value}" >> "${env_file}"
    fi
  fi
}

append_generated_value RATEBOARD_LOGS_INGEST_PASSWORD
append_generated_value GRAFANA_ADMIN_PASSWORD
chmod 0600 "${env_file}"
echo "Local logging credentials are present in .env.vagrant.local (values not printed)."
