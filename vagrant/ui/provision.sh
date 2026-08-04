#!/usr/bin/env bash
# Provisions the ui-service VM: installs Docker Engine + the Compose plugin,
# writes a .env pointed at the backend-service VM, and runs
# `docker compose up -d --build` against ui-service/docker-compose.yml (a single
# nginx container serving the production Vite build -- see ui-service/Dockerfile).
#
# Networking note: VITE_BACKEND_BASE_URL is set to the backend-service VM's bridged
# LAN IP, not localhost - import.meta.env.VITE_* is baked into the static bundle at
# build time (see ui-service/docker-compose.yml), and that bundle can run in a
# browser on *any* device on the LAN, not just this host, so "localhost:8000" would
# wrongly resolve to whichever device loaded the page. The backend's real LAN IP
# works from the host and from every other device alike. This guest itself also
# uses that same IP for the readiness check below. The container uses
# network_mode: host, so it binds to this VM's own bridged IP on port 5173, same
# as the old vite dev server did.
set -euo pipefail

APP_DIR="/app"
BACKEND_IP="192.168.0.221"

export DEBIAN_FRONTEND=noninteractive

# Ubuntu's unattended-upgrades runs automatically shortly after boot and holds the
# dpkg lock while it does; without -o DPkg::Lock::Timeout, apt-get fails immediately
# instead of waiting for it, making provisioning fail intermittently depending on how
# the timing lands. 300s comfortably outlasts a typical unattended-upgrades run.
APT="apt-get -o DPkg::Lock::Timeout=300"

if ! command -v docker >/dev/null 2>&1; then
  echo ">>> Installing Docker Engine + Compose plugin"
  $APT update -y
  $APT install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  ARCH="$(dpkg --print-architecture)"
  CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"
  echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  $APT update -y
  $APT install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  systemctl enable --now docker
  usermod -aG docker vagrant
fi

echo ">>> Creating sky user (docker group member)"
if ! id -u sky >/dev/null 2>&1; then
  useradd -m -s /bin/bash sky
  install -d -m 700 -o sky -g sky /home/sky/.ssh
  echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILzfD7LC8tdDbnpi5ozVF3Jsws3GNL0DXkF8bljj4avI sky@vagrant-vms" > /home/sky/.ssh/authorized_keys
  chmod 600 /home/sky/.ssh/authorized_keys
  chown sky:sky /home/sky/.ssh/authorized_keys
fi
usermod -aG docker sky

echo ">>> Waiting for backend-service (${BACKEND_IP}:8000) to respond"
$APT install -y curl
for i in $(seq 1 30); do
  if curl -fsS -o /dev/null "http://${BACKEND_IP}:8000/docs"; then
    echo "    backend-service is up"
    break
  fi
  echo "    attempt ${i}/30: not ready yet, retrying in 2s"
  sleep 2
done

echo ">>> Writing ${APP_DIR}/.env"
cd "${APP_DIR}"
[ -f .env ] || cp .env.example .env
sed -i "s#^VITE_BACKEND_BASE_URL=.*#VITE_BACKEND_BASE_URL=http://${BACKEND_IP}:8000#" .env

echo ">>> Building and starting ui-service"
docker compose up -d --build

echo ">>> Provisioning complete"
echo "    UI Service reachable at http://192.168.0.223:5173 from this Mac or any other device on the LAN"
