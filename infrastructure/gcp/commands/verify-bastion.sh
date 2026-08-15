#!/usr/bin/env bash

set -uo pipefail

hosts=(oilpricetracker-db oilpricetracker-history oilpricetracker-fetcher oilpricetracker-ui)
failures=0

for host in "${hosts[@]}"; do
  printf '\n==> Connecting to %s through the bastion\n' "${host}"

  if ssh -o BatchMode=yes -o ConnectTimeout=10 "${host}" 'bash -s' <<'REMOTE'
set -eu

file="${HOME}/bastion-hello.txt"
hostname_value="$(hostname)"
message="Hello world from ${hostname_value}!"
internal_ip="$(hostname -I | awk '{print $1}')"
bastion_peer="${SSH_CONNECTION%% *}"

printf '%s\n' "${message}" > "${file}"

printf 'Connected successfully: host=%s user=%s\n' "${hostname_value}" "$(id -un)"
printf 'Created successfully: %s\n' "${file}"
printf 'File contents: '
cat "${file}"
printf 'Extra check: internal_ip=%s bastion_peer=%s uptime=%s\n' \
  "${internal_ip}" "${bastion_peer}" "$(uptime -p)"
REMOTE
  then
    printf '<== Connection to host %s completed successfully\n' "${host}"
  else
    printf '<== %s failed\n' "${host}" >&2
    failures=$((failures + 1))
  fi
done

printf '\nFinished: %d succeeded, %d failed\n' \
  "$(( ${#hosts[@]} - failures ))" "${failures}"

((failures == 0))
