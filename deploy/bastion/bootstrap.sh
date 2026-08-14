#!/usr/bin/env bash

set -euo pipefail

JUMP_USER="${JUMP_USER:-jumpuser}"
JUMP_PORT="${JUMP_PORT:-48002}"

echo "[1/7] Creating jump user..."

if ! id "${JUMP_USER}" >/dev/null 2>&1; then
    useradd \
        --create-home \
        --shell /usr/sbin/nologin \
        "${JUMP_USER}"
fi

install \
    -d \
    -m 700 \
    -o "${JUMP_USER}" \
    -g "${JUMP_USER}" \
    "/home/${JUMP_USER}/.ssh"


echo "[2/7] Configuring sshd..."

cat > /etc/ssh/sshd_config.d/99-bastion.conf <<EOF
Port 22
Port ${JUMP_PORT}

PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no

X11Forwarding no

Match User ${JUMP_USER}
    PasswordAuthentication no
    PubkeyAuthentication yes
    AllowTcpForwarding yes
    X11Forwarding no
    PermitTTY no
EOF


echo "[3/7] Configuring systemd SSH socket..."

mkdir -p /etc/systemd/system/ssh.socket.d

cat > /etc/systemd/system/ssh.socket.d/override.conf <<EOF
[Socket]
ListenStream=
ListenStream=0.0.0.0:22
ListenStream=[::]:22
ListenStream=0.0.0.0:${JUMP_PORT}
ListenStream=[::]:${JUMP_PORT}
EOF


echo "[4/7] Checking sshd configuration..."

sshd -t


echo "[5/7] Reloading systemd..."

systemctl daemon-reload
systemctl restart ssh.socket
systemctl restart ssh.service


echo "[6/7] Checking listeners..."

ss -lntp | grep -E ":22|:${JUMP_PORT}" || true


echo "[7/7] Done."

echo
echo "Bastion configuration applied."
echo "Admin SSH: tcp/22"
echo "Jump SSH:  tcp/${JUMP_PORT}"
echo "Jump user: ${JUMP_USER}"
echo
echo "Public key must be placed in:"
echo "/home/${JUMP_USER}/.ssh/authorized_keys"