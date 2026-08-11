#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=infrastructure/vagrant/commands/host-lib.sh
source "${SCRIPT_DIR}/host-lib.sh"
load_host_config
cd "${HOST_PROJECT_ROOT}"
"${SCRIPT_DIR}/ssh-setup.sh"
provider="$(resolve_vagrant_provider)"

machine="${1:-}"
case "${machine}" in
  database|history|fetcher|ui) ;;
  *)
    printf 'Usage: %s {database|history|fetcher|ui}\n' "$0" >&2
    exit 2
    ;;
esac

if [[ "${provider}" == "qemu" ]]; then
  run_vagrant rsync "${machine}"
fi
run_vagrant provision "${machine}"
