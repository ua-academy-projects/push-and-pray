#!/usr/bin/env bash
set -euo pipefail

readonly PYTHON_BIN="python3.14"
readonly APP_USER="aegis"
readonly APP_ROOT="/opt/aegis"
readonly CONFIG_DIRECTORY="/etc/aegis"
readonly STATE_DIRECTORY="/var/lib/aegis"
readonly BASE_MARKER="${STATE_DIRECTORY}/.base-provisioned"
readonly DEV_USER="lord"
readonly DEV_KEY_FILE="/tmp/devops_train.pub"

fail() {
  echo "Aegis base provisioning failed: $*" >&2
  exit 1
}

progress() {
  echo "==> Aegis base: $*"
}

[[ "${EUID}" -eq 0 ]] || fail "run this provisioner as root"

export DEBIAN_FRONTEND=noninteractive

progress "refreshing Ubuntu package metadata"
apt-get update

# Ubuntu 24.04 does not ship the repository-required Python 3.14 in every base
# image. Add deadsnakes only when apt cannot already resolve that interpreter.
if ! apt-cache show "${PYTHON_BIN}" >/dev/null 2>&1; then
  progress "enabling the Python package repository for ${PYTHON_BIN}"
  apt-get install --yes --no-install-recommends \
    ca-certificates \
    software-properties-common
  if ! grep -Rqs \
    "ppa.launchpadcontent.net/deadsnakes/ppa" \
    /etc/apt/sources.list /etc/apt/sources.list.d; then
    add-apt-repository --yes ppa:deadsnakes/ppa
    apt-get update
  fi
fi

progress "installing Python, build, database, and diagnostic tools"
apt-get install --yes --no-install-recommends \
  amqp-tools \
  build-essential \
  ca-certificates \
  curl \
  git \
  jq \
  libmariadb-dev \
  libmariadb-dev-compat \
  mariadb-client \
  pkg-config \
  python3-pip \
  python3.14 \
  python3.14-dev \
  python3.14-venv \
  redis-tools \
  rsync

command -v "${PYTHON_BIN}" >/dev/null || fail "${PYTHON_BIN} is unavailable"
command -v git >/dev/null || fail "Git is unavailable"
command -v curl >/dev/null || fail "curl is unavailable"
command -v jq >/dev/null || fail "jq is unavailable"
command -v mariadb >/dev/null || fail "MariaDB client is unavailable"
command -v redis-cli >/dev/null || fail "Redis CLI is unavailable"
command -v amqp-declare-queue >/dev/null || \
  fail "RabbitMQ AMQP diagnostic tools are unavailable"

if ! id "${APP_USER}" >/dev/null 2>&1; then
  progress "creating the restricted ${APP_USER} service account"
  useradd \
    --system \
    --home-dir "${APP_ROOT}" \
    --shell /usr/sbin/nologin \
    --user-group \
    "${APP_USER}"
fi

if [[ -f "${DEV_KEY_FILE}" ]]; then
  if ! id "${DEV_USER}" >/dev/null 2>&1; then
  progress "creating the ${DEV_USER} user for SSH access"
  useradd -m -s /bin/bash "${DEV_USER}"
  echo "${DEV_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${DEV_USER}"
  fi

  progress "injection SSH key for ${DEV_USER}"
  install -d -o "${DEV_USER}" -g "${DEV_USER}" -m 0700 "/home/${DEV_USER}/.ssh"
  install -o "${DEV_USER}" -g "${DEV_USER}" -m 0600 "${DEV_KEY_FILE}" "/home/${DEV_USER}/.ssh/authorized_keys"
  rm -f "${DEV_KEY_FILE}"
fi

progress "preparing application, configuration, and state directories"
install -d -o "${APP_USER}" -g "${APP_USER}" -m 0750 \
  "${APP_ROOT}" \
  "${STATE_DIRECTORY}"
install -d -o root -g "${APP_USER}" -m 0750 "${CONFIG_DIRECTORY}"

# Application logs go to container stdout/stderr and remain available through
# `docker logs`; no application-owned host log directory is required.
touch "${BASE_MARKER}"
chown "${APP_USER}:${APP_USER}" "${BASE_MARKER}"
chmod 0640 "${BASE_MARKER}"

progress "verified ${PYTHON_BIN} and base development dependencies"
