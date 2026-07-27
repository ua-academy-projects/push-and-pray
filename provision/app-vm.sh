#!/usr/bin/env bash
set -euo pipefail

readonly SERVICE_NAME="${1:-}"
readonly PACKAGE_NAME="${2:-}"
readonly PYTHON_BIN="python3.14"
readonly APP_ROOT="/opt/aegis"
readonly BASE_MARKER="/var/lib/aegis/.base-provisioned"
readonly SERVICE_DIR="${APP_ROOT}/${SERVICE_NAME}"
readonly SOURCE_DIR="/vagrant/services/${SERVICE_NAME}"
readonly VENV_DIR="${SERVICE_DIR}/.venv"

fail() {
  echo "Aegis application provisioning failed: $*" >&2
  exit 1
}

case "${SERVICE_NAME}:${PACKAGE_NAME}" in
  ui-service:ui_service|history-service:history_service|provider-service:provider_service)
    ;;
  *)
    fail "unsupported service/package pair '${SERVICE_NAME}:${PACKAGE_NAME}'"
    ;;
esac

[[ -f "${SOURCE_DIR}/pyproject.toml" ]] || fail "missing ${SOURCE_DIR}/pyproject.toml"
[[ -d "${SOURCE_DIR}/src/${PACKAGE_NAME}" ]] || fail "missing service package source"
[[ -f "${BASE_MARKER}" ]] || \
  fail "base dependencies are missing; run provision/base-vm.sh first"
command -v "${PYTHON_BIN}" >/dev/null || fail "${PYTHON_BIN} is unavailable"
command -v rsync >/dev/null || fail "rsync is unavailable"

install -d -o aegis -g aegis -m 0750 "${APP_ROOT}" "${SERVICE_DIR}"

echo "==> Aegis application: synchronizing ${SERVICE_NAME}"
install -d -o aegis -g aegis -m 0750 "${SERVICE_DIR}/src"
rsync --archive --delete --chown=aegis:aegis \
  "${SOURCE_DIR}/src/" "${SERVICE_DIR}/src/"
install -o aegis -g aegis -m 0644 \
  "${SOURCE_DIR}/pyproject.toml" \
  "${SERVICE_DIR}/pyproject.toml"

if [[ "${SERVICE_NAME}" == "history-service" ]]; then
  install -d -o aegis -g aegis -m 0750 "${SERVICE_DIR}/alembic"
  install -o aegis -g aegis -m 0644 \
    "${SOURCE_DIR}/alembic.ini" \
    "${SERVICE_DIR}/alembic.ini"
  rsync --archive --delete --chown=aegis:aegis \
    "${SOURCE_DIR}/alembic/" "${SERVICE_DIR}/alembic/"
fi

if [[ ! -x "${VENV_DIR}/bin/python" ]]; then
  echo "==> Aegis application: creating ${SERVICE_NAME} virtual environment"
  runuser -u aegis -- "${PYTHON_BIN}" -m venv "${VENV_DIR}"
elif ! "${VENV_DIR}/bin/python" -c \
  'import sys; raise SystemExit(sys.version_info[:2] != (3, 14))'; then
  fail "${VENV_DIR} does not use Python 3.14; remove that service venv and reprovision"
fi

run_as_aegis() {
  runuser -u aegis -- env \
    HOME="${APP_ROOT}" \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_INPUT=1 \
    "$@"
}

echo "==> Aegis application: installing ${SERVICE_NAME}"
run_as_aegis "${VENV_DIR}/bin/python" -m pip install --upgrade pip || \
  fail "pip bootstrap failed for ${SERVICE_NAME}"
run_as_aegis "${VENV_DIR}/bin/python" -m pip install --editable "${SERVICE_DIR}" || \
  fail "dependency installation failed for ${SERVICE_NAME}"

run_as_aegis "${VENV_DIR}/bin/python" -c "import ${PACKAGE_NAME}" || \
  fail "package import verification failed for ${PACKAGE_NAME}"

[[ -x "${VENV_DIR}/bin/uvicorn" ]] || \
  fail "uvicorn entry point is missing for ${SERVICE_NAME}"

case "${SERVICE_NAME}" in
  history-service)
    [[ -x "${VENV_DIR}/bin/aegis-history-blacklist-consumer" ]] || \
      fail "History blacklist consumer entry point is missing"
    ;;
  provider-service)
    [[ -x "${VENV_DIR}/bin/aegis-provider-blacklist-worker" ]] || \
      fail "Provider blacklist worker entry point is missing"
    ;;
  ui-service)
    ;;
esac

echo "Verified ${PACKAGE_NAME} with ${VENV_DIR}/bin/python"
