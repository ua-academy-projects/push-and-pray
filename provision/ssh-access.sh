#!/usr/bin/env bash

set -Eeuo pipefail

log() {
    printf '\n[%s] %s\n' "$(date --iso-8601=seconds)" "$*"
}

SSH_USER="${AIRAWARE_SSH_USER:-airaware}"
PUBLIC_KEY="${AIRAWARE_SSH_PUBLIC_KEY:-}"

if [[ -z "${PUBLIC_KEY//[[:space:]]/}" ]]; then
    log "AIRAWARE_SSH_PUBLIC_KEY is not set; custom SSH access was not configured"
    log "Vagrant-managed SSH remains available through: vagrant ssh <vm>"
    exit 0
fi

if [[ ! "${PUBLIC_KEY}" =~ ^ssh-(ed25519|rsa|ecdsa-[^[:space:]]+)[[:space:]]+ ]]; then
    echo "AIRAWARE_SSH_PUBLIC_KEY does not look like a valid OpenSSH public key" >&2
    exit 1
fi

log "Configuring public-key SSH access for user ${SSH_USER}"

export DEBIAN_FRONTEND=noninteractive
apt-get install -y openssh-server sudo
systemctl enable --now ssh

if id "${SSH_USER}" >/dev/null 2>&1; then
    usermod --shell /bin/bash "${SSH_USER}"
else
    useradd \
        --create-home \
        --shell /bin/bash \
        "${SSH_USER}"
fi

USER_HOME="$(getent passwd "${SSH_USER}" | cut -d: -f6)"
if [[ -z "${USER_HOME}" ]]; then
    echo "Could not determine home directory for ${SSH_USER}" >&2
    exit 1
fi

# The existing AirAware service account uses /opt/airaware as its home.
# Keep that location when it already exists and secure its SSH directory.
install -d -o "${SSH_USER}" -g "${SSH_USER}" -m 0700 "${USER_HOME}/.ssh"
touch "${USER_HOME}/.ssh/authorized_keys"
chown "${SSH_USER}:${SSH_USER}" "${USER_HOME}/.ssh/authorized_keys"
chmod 0600 "${USER_HOME}/.ssh/authorized_keys"

if ! grep -qxF "${PUBLIC_KEY}" "${USER_HOME}/.ssh/authorized_keys"; then
    printf '%s\n' "${PUBLIC_KEY}" >> "${USER_HOME}/.ssh/authorized_keys"
fi

usermod -aG sudo "${SSH_USER}"
if getent group docker >/dev/null 2>&1; then
    usermod -aG docker "${SSH_USER}"
fi

cat > "/etc/sudoers.d/${SSH_USER}" <<EOF_SUDO
${SSH_USER} ALL=(ALL) NOPASSWD:ALL
EOF_SUDO
chmod 0440 "/etc/sudoers.d/${SSH_USER}"
visudo -cf "/etc/sudoers.d/${SSH_USER}" >/dev/null

# Do not restrict AllowUsers or disable the vagrant account. Vagrant keeps
# using its own key as a recovery and provisioning path.
cat > /etc/ssh/sshd_config.d/60-airaware-public-key.conf <<'EOF_SSHD'
PubkeyAuthentication yes
PermitRootLogin no
EOF_SSHD

sshd -t
systemctl reload ssh

log "SSH access configured"
log "User: ${SSH_USER}"
log "Home: ${USER_HOME}"
