#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=infrastructure/vagrant/commands/host-lib.sh
source "${SCRIPT_DIR}/host-lib.sh"
load_host_config
cd "${HOST_PROJECT_ROOT}"

printf '%-10s %-15s %s\n' 'VM' 'LAN IP' 'ENDPOINT'
printf '%-10s %-15s %s\n' '----------' '---------------' '--------'

for machine in database history fetcher ui; do
  lan_ip="$(lan_ip_for "${machine}")"
  if [[ -z "${lan_ip}" ]]; then
    lan_ip='not-found'
    endpoint='public adapter has no address'
  else
    endpoint="$(service_url_for "${machine}" "${lan_ip}")"
  fi
  printf '%-10s %-15s %s\n' "${machine}" "${lan_ip}" "${endpoint}"
done
