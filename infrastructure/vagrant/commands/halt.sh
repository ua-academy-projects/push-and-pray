#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=infrastructure/vagrant/commands/host-lib.sh
source "${SCRIPT_DIR}/host-lib.sh"
load_host_config
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
cd "${PROJECT_ROOT}"
run_vagrant halt ui fetcher history database
