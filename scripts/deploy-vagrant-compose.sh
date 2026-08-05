#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script with sudo because vagrant-qemu vmnet_bridged requires it." >&2
  exit 1
fi

for file in .env .env.vagrant.local; do
  [[ -f "${file}" ]] || { echo "Missing ${ROOT_DIR}/${file}" >&2; exit 1; }
done

"${ROOT_DIR}/scripts/ensure-local-logging-env.sh"
"${ROOT_DIR}/scripts/update-local-ssh-config.sh"
"${ROOT_DIR}/scripts/update-local-hosts.sh"

vagrant up logs database rabbitmq backend-service api-fetcher ui --provider=qemu
vagrant rsync
vagrant provision logs
vagrant provision database
vagrant provision rabbitmq
vagrant provision backend-service
vagrant provision api-fetcher
vagrant provision ui

"${ROOT_DIR}/scripts/check-vm-deployment.sh"
