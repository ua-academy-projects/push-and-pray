#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=infrastructure/vagrant/commands/host-lib.sh
source "${SCRIPT_DIR}/host-lib.sh"
cd "${PROJECT_ROOT}"

if [[ ! -f infrastructure/vagrant/config/vagrant.env ]]; then
  cp infrastructure/vagrant/config/vagrant.env.example infrastructure/vagrant/config/vagrant.env
  printf 'Created infrastructure/vagrant/config/vagrant.env. Review QEMU_VMNET_INTERFACE, LAN_CIDR and static IPs, then run this script again.\n'
  exit 1
fi

if [[ ! -f .env ]]; then
  printf 'Missing .env. Copy .env.example and set OILPRICEAPI_KEY first.\n' >&2
  exit 1
fi

if ! awk -F= '$1 == "OILPRICEAPI_KEY" && $2 != "" && $2 != "replace-me" { found=1 } END { exit !found }' .env; then
  printf 'OILPRICEAPI_KEY is not configured in .env.\n' >&2
  exit 1
fi

load_host_config
"${SCRIPT_DIR}/ssh-setup.sh"
"${SCRIPT_DIR}/preflight.sh"

if ! vagrant box list | awk \
  -v box="${VAGRANT_BOX}" \
  -v provider="qemu" \
  -v version="${VAGRANT_BOX_VERSION:-}" \
  '$1 == box &&
   index($0, "(" provider ",") &&
   (version == "" || index($0, ", " version ",") || index($0, ", " version ")")) {
     found=1
   }
   END { exit !found }'; then
  printf '\n=== Downloading %s for %s as the current user ===\n' \
    "${VAGRANT_BOX}" "qemu"
  box_add_args=(
    "${VAGRANT_BOX}"
    "--provider=qemu"
    "--architecture=${VAGRANT_BOX_ARCHITECTURE:-arm64}"
  )
  if [[ -n "${VAGRANT_BOX_VERSION:-}" ]]; then
    box_add_args+=("--box-version=${VAGRANT_BOX_VERSION}")
  fi
  vagrant box add "${box_add_args[@]}"
fi

run_vagrant validate

for machine in database history fetcher ui; do
  printf '\n=== Starting %s ===\n' "${machine}"
  run_vagrant up "${machine}" --provider=qemu --provision
done

"${SCRIPT_DIR}/show-ips.sh"
"${SCRIPT_DIR}/verify.sh"
