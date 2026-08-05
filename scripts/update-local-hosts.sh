#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env.vagrant.local"
HOSTS_FILE="/etc/hosts"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script with sudo: sudo ./scripts/update-local-hosts.sh" >&2
  exit 1
fi

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}" >&2
  exit 1
fi

read_value() {
  local name="$1"
  awk -F= -v key="${name}" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "${ENV_FILE}"
}

UI_IP="$(read_value RATEBOARD_UI_IP)"
API_FETCHER_IP="$(read_value RATEBOARD_API_FETCHER_IP)"
BACKEND_SERVICE_IP="$(read_value RATEBOARD_BACKEND_SERVICE_IP)"
DATABASE_IP="$(read_value RATEBOARD_DATABASE_IP)"
RABBITMQ_IP="$(read_value RATEBOARD_RABBITMQ_IP)"
LOGS_IP="$(read_value RATEBOARD_LOGS_IP)"

for address in "${UI_IP}" "${API_FETCHER_IP}" "${BACKEND_SERVICE_IP}" "${DATABASE_IP}" "${RABBITMQ_IP}" "${LOGS_IP}"; do
  if [[ ! "${address}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    echo "Invalid Rateboard IPv4 address in ${ENV_FILE}: ${address}" >&2
    exit 1
  fi
done

temporary_hosts="$(mktemp)"
trap 'rm -f "${temporary_hosts}"' EXIT

awk '
  $0 == "# rateboard-local-begin" { managed = 1; next }
  $0 == "# rateboard-local-end" { managed = 0; next }
  managed { next }
  /(^|[[:space:]])(rateboard\.test|rates-ui|rates-api-fetcher|rates-backend-service|rates-db|rates-rabbitmq|rates-logs)([[:space:]]|$)/ { next }
  { print }
' "${HOSTS_FILE}" > "${temporary_hosts}"

{
  echo "# rateboard-local-begin"
  printf "%s rates-ui rateboard.test\n" "${UI_IP}"
  printf "%s rates-api-fetcher\n" "${API_FETCHER_IP}"
  printf "%s rates-backend-service\n" "${BACKEND_SERVICE_IP}"
  printf "%s rates-db\n" "${DATABASE_IP}"
  printf "%s rates-rabbitmq\n" "${RABBITMQ_IP}"
  printf "%s rates-logs\n" "${LOGS_IP}"
  echo "# rateboard-local-end"
} >> "${temporary_hosts}"

cp "${temporary_hosts}" "${HOSTS_FILE}"
chmod 0644 "${HOSTS_FILE}"
echo "Updated ${HOSTS_FILE}: rateboard.test -> ${UI_IP}, rates-logs -> ${LOGS_IP}"
