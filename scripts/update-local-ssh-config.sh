#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_file="${root_dir}/.env.vagrant.local"
[[ -f "${env_file}" ]] || { echo "Missing ${env_file}" >&2; exit 1; }

read_value() {
  local name="$1"
  awk -F= -v key="${name}" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "${env_file}"
}

ssh_user="$(read_value RATEBOARD_SSH_USERNAME)"
identity_file="$(read_value RATEBOARD_SSH_IDENTITY_FILE)"
[[ "${ssh_user}" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || { echo "Invalid RATEBOARD_SSH_USERNAME" >&2; exit 1; }
[[ "${identity_file}" == /* && -f "${identity_file}" ]] || { echo "Invalid RATEBOARD_SSH_IDENTITY_FILE" >&2; exit 1; }

if [[ "${EUID}" -eq 0 ]]; then
  local_user="${SUDO_USER:-}"
  [[ -n "${local_user}" && "${local_user}" != root ]] || {
    echo "Run as your local user or through sudo with SUDO_USER preserved." >&2
    exit 1
  }
  if command -v dscl >/dev/null 2>&1; then
    local_home="$(dscl . -read "/Users/${local_user}" NFSHomeDirectory | awk '{print $2}')"
  else
    local_home="$(getent passwd "${local_user}" | cut -d: -f6)"
  fi
else
  local_user="$(id -un)"
  local_home="${HOME}"
fi

ssh_dir="${local_home}/.ssh"
config_file="${ssh_dir}/config"
temporary_config="$(mktemp "${local_home}/.ssh-config.XXXXXX")"
trap 'rm -f "${temporary_config}"' EXIT
install -d -m 0700 "${ssh_dir}"

if [[ -f "${config_file}" ]]; then
  awk '
    $0 == "# rateboard-ssh-begin" { managed = 1; next }
    $0 == "# rateboard-ssh-end" { managed = 0; next }
    !managed { print }
  ' "${config_file}" > "${temporary_config}"
fi

append_host() {
  local aliases="$1"
  local address="$2"
  {
    printf 'Host %s\n' "${aliases}"
    printf '  HostName %s\n' "${address}"
    printf '  User %s\n' "${ssh_user}"
    printf '  IdentityFile %s\n' "${identity_file}"
    echo '  IdentitiesOnly yes'
    echo '  StrictHostKeyChecking accept-new'
    printf '  UserKnownHostsFile %s/.ssh/known_hosts_rateboard\n' "${local_home}"
  } >> "${temporary_config}"
}

{
  echo '# rateboard-ssh-begin'
  echo '# Managed by scripts/update-local-ssh-config.sh.'
} >> "${temporary_config}"
append_host 'ui rates-ui' "$(read_value RATEBOARD_UI_IP)"
append_host 'api-fetcher rates-api-fetcher' "$(read_value RATEBOARD_API_FETCHER_IP)"
append_host 'backend-service rates-backend-service' "$(read_value RATEBOARD_BACKEND_SERVICE_IP)"
append_host 'database rates-db' "$(read_value RATEBOARD_DATABASE_IP)"
append_host 'rabbitmq rates-rabbitmq' "$(read_value RATEBOARD_RABBITMQ_IP)"
append_host 'logs rates-logs' "$(read_value RATEBOARD_LOGS_IP)"
echo '# rateboard-ssh-end' >> "${temporary_config}"

install -m 0600 "${temporary_config}" "${config_file}"
if [[ "${EUID}" -eq 0 ]]; then
  chown "${local_user}" "${ssh_dir}" "${config_file}"
fi
echo "Updated ${config_file} with Rateboard SSH aliases for user ${ssh_user}."
