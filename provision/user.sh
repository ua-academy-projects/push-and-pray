#!/usr/bin/env bash
set -euo pipefail

: "${VM_SSH_USER:?VM_SSH_USER is required}"
: "${VM_SSH_PUBLIC_KEY:?VM_SSH_PUBLIC_KEY is required}"

if [[ ! "$VM_SSH_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
  echo "Invalid VM_SSH_USER: $VM_SSH_USER" >&2
  exit 1
fi

if ! id "$VM_SSH_USER" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$VM_SSH_USER"
fi

user_home=$(getent passwd "$VM_SSH_USER" | cut -d: -f6)
user_group=$(id -gn "$VM_SSH_USER")
ssh_dir="$user_home/.ssh"
authorized_keys="$ssh_dir/authorized_keys"

install -d -m 700 -o "$VM_SSH_USER" -g "$user_group" "$ssh_dir"
touch "$authorized_keys"
chmod 600 "$authorized_keys"
chown "$VM_SSH_USER:$user_group" "$authorized_keys"

if ! grep -qxF "$VM_SSH_PUBLIC_KEY" "$authorized_keys"; then
  printf '%s\n' "$VM_SSH_PUBLIC_KEY" >> "$authorized_keys"
fi

cat > "/etc/sudoers.d/$VM_SSH_USER" <<EOF
$VM_SSH_USER ALL=(ALL) NOPASSWD:ALL
EOF
chmod 440 "/etc/sudoers.d/$VM_SSH_USER"
visudo --check --file="/etc/sudoers.d/$VM_SSH_USER"
