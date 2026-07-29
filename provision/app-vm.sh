#!/usr/bin/env bash
set -euo pipefail

readonly SERVICE_NAME="${1:-}"
readonly PACKAGE_NAME="${2:-}"
readonly BASE_MARKER="/var/lib/aegis/.base-provisioned"

fail() {
  echo "Aegis container-host provisioning failed: $*" >&2
  exit 1
}

progress() {
  echo "==> Aegis ${SERVICE_NAME}: $*"
}

case "${SERVICE_NAME}:${PACKAGE_NAME}" in
  ui-service:ui_service|history-service:history_service|provider-service:provider_service)
    ;;
  *)
    fail "unsupported service/package pair '${SERVICE_NAME}:${PACKAGE_NAME}'"
    ;;
esac

[[ -f "${BASE_MARKER}" ]] || \
  fail "base dependencies are missing; run provision/base-vm.sh first"
[[ -f "/vagrant/services/${SERVICE_NAME}/Dockerfile" ]] || \
  fail "missing ${SERVICE_NAME} Dockerfile"

export DEBIAN_FRONTEND=noninteractive
progress "installing Docker Engine and Docker Compose plugin"
apt-get update
apt-get install --yes --no-install-recommends docker.io docker-compose-v2

systemctl enable --now docker.service
docker info >/dev/null || fail "Docker Engine is unavailable"
docker compose version >/dev/null || fail "Docker Compose plugin is unavailable"

# Remove the former host-installed application tree. Runtime source and
# dependencies now exist only in the immutable service image.
rm -rf "/opt/aegis/${SERVICE_NAME}"

progress "container host is ready"
