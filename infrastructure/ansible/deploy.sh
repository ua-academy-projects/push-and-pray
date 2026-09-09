#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Wrapper around ansible-playbook that refuses to report success when the
# given inventory/--limit combination resolves to zero hosts across the
# whole run.
#
# Why this exists: Ansible has no way to make a play run "regardless of
# --limit" - --limit intersects with every play's own `hosts:` pattern
# independently. preflight.yml's own checks (see
# oilscope/platform/playbooks/tasks/preflight_checks.yml) close most of "the
# inventory or --limit ends up touching the wrong/incomplete set of hosts",
# but they are themselves plays - a --limit pattern that happens to exclude
# every host in BOTH of them, including localhost, means neither preflight
# play runs either. There is nothing left inside Ansible's own playbook
# execution model to catch that combination; it has to be caught outside it.
#
# This script is that outside check: it asks Ansible itself, via
# --list-hosts (which performs no side effects - no connection, no task
# execution), whether this exact invocation would touch anything at all,
# before running it for real.
#
# Usage: identical to ansible-playbook - pass the same arguments through.
#
#   infrastructure/ansible/deploy.sh oilscope.platform.deploy_workloads \
#     -i infrastructure/ansible/inventory/oilscope-aws.yml \
#     -e project_config_path=/absolute/path/project-config.json
#
# Known limitation: the --list-hosts pre-check is a separate ansible-playbook
# invocation with the same arguments, so a flag that prompts for input
# (--ask-become-pass, --ask-vault-pass, ...) prompts twice - once here, once
# for the real run below.
set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "usage: $0 <ansible-playbook arguments>" >&2
  exit 2
fi

list_output="$(ansible-playbook "$@" --list-hosts 2>&1)" || {
  printf '%s\n' "${list_output}" >&2
  echo "error: 'ansible-playbook --list-hosts' itself failed - see output above." >&2
  exit 1
}

total_hosts=0
while read -r count; do
  total_hosts=$((total_hosts + count))
done < <(printf '%s\n' "${list_output}" | grep -oE 'hosts \([0-9]+\):' | grep -oE '[0-9]+')

if [ "${total_hosts}" -eq 0 ]; then
  printf '%s\n' "${list_output}" >&2
  echo >&2
  echo "error: this inventory/--limit combination matches zero hosts across every play in this run." >&2
  echo "Refusing to report success for a run that would touch nothing - see the --list-hosts output above for why." >&2
  exit 1
fi

exec ansible-playbook "$@"
