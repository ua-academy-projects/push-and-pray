#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=infrastructure/vagrant/commands/host-lib.sh
source "${SCRIPT_DIR}/host-lib.sh"
load_host_config
cd "${HOST_PROJECT_ROOT}"

case "${1:-}" in
  database)
    ssh_target=database
    tag=petroscope/postgres
    ;;
  rabbitmq)
    ssh_target=history
    tag=petroscope/rabbitmq
    ;;
  history)
    ssh_target=history
    tag=petroscope/history
    ;;
  fetcher)
    ssh_target=fetcher
    tag=petroscope/fetcher
    ;;
  redis)
    ssh_target=app
    tag=petroscope/redis
    ;;
  ui)
    ssh_target=app
    tag=petroscope/ui
    ;;
  *)
    printf 'Usage: %s {database|rabbitmq|history|fetcher|redis|ui} [--follow] [lines]\n' "$0" >&2
    exit 2
    ;;
esac

shift
follow_flag=""
lines=100
for argument in "$@"; do
  case "${argument}" in
    --follow|-f) follow_flag="--follow" ;;
    *[!0-9]*|'')
      printf 'Unknown argument: %s\n' "${argument}" >&2
      exit 2
      ;;
    *) lines="${argument}" ;;
  esac
done

ssh "${ssh_target}" \
  "journalctl --no-pager --output=short-iso --lines=${lines} ${follow_flag} CONTAINER_TAG=${tag}"
