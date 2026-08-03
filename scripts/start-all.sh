#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Rateboard now runs in five Vagrant VM Compose projects." >&2
  echo "Run: sudo ${ROOT_DIR}/scripts/start-all.sh" >&2
  exit 1
fi

exec "${ROOT_DIR}/scripts/deploy-vagrant-compose.sh"
