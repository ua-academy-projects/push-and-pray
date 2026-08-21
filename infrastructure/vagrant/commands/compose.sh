#!/usr/bin/env bash

set -Eeuo pipefail

printf 'Vagrant deployment is unsupported for issue #58. Use the cloud deployment path with Secret Manager.\n' >&2
exit 1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=infrastructure/vagrant/commands/host-lib.sh
source "${SCRIPT_DIR}/host-lib.sh"
load_host_config
cd "${HOST_PROJECT_ROOT}"

role="${1:-}"
case "${role}" in
  database|history|fetcher|ui) ;;
  *)
    printf 'Usage: %s {database|history|fetcher|ui} <docker compose arguments...>\n' "$0" >&2
    exit 2
    ;;
esac
shift

if (($# == 0)); then
  set -- ps
fi

printf -v compose_arguments ' %q' "$@"
run_vagrant ssh "${role}" -c \
  "sudo docker compose \
    --env-file /etc/oil-price-tracker/docker.env \
    --file /opt/oil-price-tracker/source/infrastructure/docker/compose.${role}.yaml \
    --project-name petroscope-${role}${compose_arguments}"
