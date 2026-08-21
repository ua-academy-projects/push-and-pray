#!/usr/bin/env bash

set -Eeuo pipefail

printf 'Vagrant deployment is unsupported for issue #58. Use the cloud deployment path with Secret Manager.\n' >&2
exit 1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=infrastructure/vagrant/commands/host-lib.sh
source "${SCRIPT_DIR}/host-lib.sh"
cd "${PROJECT_ROOT}"

if [[ ! -f infrastructure/vagrant/config/vagrant.env ]]; then
  printf 'Missing infrastructure/vagrant/config/vagrant.env. Create this untracked local configuration, then run this script again.\n' >&2
  exit 1
fi

load_host_config

for variable in DB_PASSWORD OILPRICEAPI_KEY RABBITMQ_USER RABBITMQ_PASSWORD; do
  if [[ -z "${!variable:-}" ]]; then
    printf '%s must be set in the current process environment.\n' "${variable}" >&2
    exit 1
  fi
done

if [[ "${DB_PASSWORD}" == "change-me" || "${RABBITMQ_PASSWORD}" == "change-me" || "${OILPRICEAPI_KEY}" == "replace-me" ]]; then
  printf 'Replace default deployment secrets in the current process environment.\n' >&2
  exit 1
fi

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
