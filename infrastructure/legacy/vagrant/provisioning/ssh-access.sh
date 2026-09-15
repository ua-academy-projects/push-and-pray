#!/usr/bin/env bash

set -Eeuo pipefail

# shellcheck source=infrastructure/vagrant/provisioning/lib.sh
source /vagrant/infrastructure/vagrant/provisioning/lib.sh
load_project_config

: "${SSH_ADMIN_USER:?SSH_ADMIN_USER is required in infrastructure/vagrant/config/vagrant.env}"

if [[ ! "${SSH_ADMIN_USER}" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
  log "SSH_ADMIN_USER must be a valid Linux username"
  exit 1
fi

uploaded_key="/tmp/oil-tracker-admin.pub"
if [[ ! -s "${uploaded_key}" ]]; then
  log "Missing uploaded SSH public key: ${uploaded_key}"
  exit 1
fi

if ! ssh-keygen -l -f "${uploaded_key}" >/dev/null 2>&1; then
  log "Uploaded SSH public key is invalid"
  exit 1
fi

if ! id "${SSH_ADMIN_USER}" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "${SSH_ADMIN_USER}"
fi

# The account authenticates only by SSH key. Membership in the docker group
# permits the lab operator to inspect and manage this VM's Compose project.
usermod -aG docker "${SSH_ADMIN_USER}"
passwd --lock "${SSH_ADMIN_USER}" >/dev/null

admin_home="$(getent passwd "${SSH_ADMIN_USER}" | cut -d: -f6)"
install -d -o "${SSH_ADMIN_USER}" -g "${SSH_ADMIN_USER}" -m 0700 \
  "${admin_home}/.ssh"
install -o "${SSH_ADMIN_USER}" -g "${SSH_ADMIN_USER}" -m 0600 \
  "${uploaded_key}" "${admin_home}/.ssh/authorized_keys"
rm -f "${uploaded_key}"

log "Dedicated SSH account ${SSH_ADMIN_USER} is ready on $(hostname)"
