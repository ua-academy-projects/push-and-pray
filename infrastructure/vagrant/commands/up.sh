#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=infrastructure/vagrant/commands/host-lib.sh
source "${SCRIPT_DIR}/host-lib.sh"
cd "${PROJECT_ROOT}"

if [[ ! -f infrastructure/vagrant/config/vagrant.env ]]; then
  cp infrastructure/vagrant/config/vagrant.env.example infrastructure/vagrant/config/vagrant.env
  printf 'Created infrastructure/vagrant/config/vagrant.env. Review the provider, network, static IPs and credentials, then run this script again.\n'
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
provider="$(resolve_vagrant_provider)"
box_name="$(vagrant_box_for "${provider}")"
box_version="$(vagrant_box_version_for "${provider}")"
box_architecture="$(vagrant_box_architecture_for "${provider}")"
"${SCRIPT_DIR}/ssh-setup.sh"
"${SCRIPT_DIR}/preflight.sh"

if ! vagrant box list | awk \
  -v box="${box_name}" \
  -v provider="${provider}" \
  -v version="${box_version}" \
  '$1 == box &&
   index($0, "(" provider ",") &&
   (version == "" || index($0, ", " version ",") || index($0, ", " version ")")) {
     found=1
   }
   END { exit !found }'; then
  printf '\n=== Downloading %s for %s as the current user ===\n' \
    "${box_name}" "${provider}"
  box_add_args=(
    "${box_name}"
    "--provider=${provider}"
  )
  if [[ -n "${box_architecture}" ]]; then
    box_add_args+=("--architecture=${box_architecture}")
  fi
  if [[ -n "${box_version}" ]]; then
    box_add_args+=("--box-version=${box_version}")
  fi
  vagrant box add "${box_add_args[@]}"
fi

run_vagrant validate

for machine in database history fetcher ui; do
  printf '\n=== Starting %s ===\n' "${machine}"
  run_vagrant up "${machine}" --provider="${provider}" --provision
done

"${SCRIPT_DIR}/show-ips.sh"
"${SCRIPT_DIR}/verify.sh"
