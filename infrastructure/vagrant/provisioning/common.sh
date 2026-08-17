#!/usr/bin/env bash

set -Eeuo pipefail

# shellcheck source=infrastructure/vagrant/provisioning/lib.sh
source /vagrant/infrastructure/vagrant/provisioning/lib.sh
load_project_config

export DEBIAN_FRONTEND=noninteractive

if [[ ! -f /var/lib/oil-price-tracker-common-ready ]]; then
  apt-get update
  apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    jq \
    netcat-openbsd \
    openssh-client \
    rsync \
    sudo
  touch /var/lib/oil-price-tracker-common-ready
fi

timedatectl set-timezone UTC

install -d -o root -g root -m 0755 "${APP_ROOT}"
install -d -o root -g root -m 0700 "${CONFIG_ROOT}"

sed -i '/# oil-price-tracker hosts begin/,/# oil-price-tracker hosts end/d' /etc/hosts
{
  printf '%s\n' '# oil-price-tracker hosts begin'
  printf '%s oil-db\n' "${DB_LAN_IP}"
  printf '%s oil-history\n' "${HISTORY_LAN_IP}"
  printf '%s oil-fetcher\n' "${FETCHER_LAN_IP}"
  printf '%s oil-ui\n' "${UI_LAN_IP}"
  printf '%s\n' '# oil-price-tracker hosts end'
} >> /etc/hosts

log "Common VM preparation complete on $(hostname)"
