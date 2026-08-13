#!/usr/bin/env bash

set -Eeuo pipefail

# shellcheck source=infrastructure/vagrant/provisioning/lib.sh
source /vagrant/infrastructure/vagrant/provisioning/lib.sh
load_project_config

: "${SSH_ADMIN_USER:?SSH_ADMIN_USER is required in infrastructure/vagrant/config/vagrant.env}"

# Keep Docker logs persistent across VM reboots, but deliberately small. These
# limits cover the complete journal on one VM, including system and Docker logs.
install -d -o root -g systemd-journal -m 2755 /var/log/journal
install -d -o root -g root -m 0755 /etc/systemd/journald.conf.d

settings_file="$(mktemp)"
trap 'rm -f "${settings_file}"' EXIT
{
  printf '%s\n' '[Journal]'
  printf '%s\n' 'Storage=persistent'
  printf '%s\n' 'Compress=yes'
  printf '%s\n' 'SystemMaxUse=200M'
  printf '%s\n' 'RuntimeMaxUse=50M'
  printf '%s\n' 'MaxRetentionSec=7day'
} > "${settings_file}"

journal_config="/etc/systemd/journald.conf.d/petroscope.conf"
if [[ ! -f "${journal_config}" ]] || ! cmp -s "${settings_file}" "${journal_config}"; then
  install -o root -g root -m 0644 "${settings_file}" "${journal_config}"
  systemctl restart systemd-journald
fi

usermod -aG systemd-journal "${SSH_ADMIN_USER}"
journalctl --flush
journalctl --vacuum-time=7d >/dev/null
journalctl --vacuum-size=200M >/dev/null

log "Persistent journald logging is ready on $(hostname): 200 MB, 7 days"
