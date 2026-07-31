#!/usr/bin/env bash
set -euo pipefail

: "${VM_SSH_USER:?VM_SSH_USER is required}"

if getent group docker >/dev/null; then
  usermod --append --groups docker "$VM_SSH_USER"
fi
