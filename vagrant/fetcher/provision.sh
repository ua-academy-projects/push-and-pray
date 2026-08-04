#!/usr/bin/env bash
# Provisions the fetcher-service VM: installs Docker Engine + the Compose plugin,
# writes a .env pointed at the backend-service VM, and runs
# `docker compose up -d --build` against fetcher-service/docker-compose.yml (a
# single container -- see fetcher-service/Dockerfile for why it's deliberately
# not scaled to more than one worker process).
#
# Networking note: all VMs are bridged onto the host's LAN (see Vagrantfile), each
# with its own fixed IP - this guest reaches backend-service directly at its
# bridged IP, no NAT/slirp gateway needed. The Fetcher never touches PostgreSQL
# directly (see docs/architecture.md). It does talk to RabbitMQ, on the postgres
# VM (see vagrant/postgres/provision.sh) -- publishing sync results there instead
# of calling the Backend over HTTP. The container uses network_mode: host, so it
# binds to this VM's own bridged IP the same way the old systemd process did.
set -euo pipefail

APP_DIR="/app"
BACKEND_IP="192.168.0.221"
RABBITMQ_IP="192.168.0.220" # same VM as postgres -- see vagrant/postgres/provision.sh
RABBITMQ_USER="skyivano"
RABBITMQ_PASS="skyivano"

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

echo ">>> Waiting for rabbitmq (${RABBITMQ_IP}:5672) to accept connections"
for i in $(seq 1 30); do
  if (exec 3<>"/dev/tcp/${RABBITMQ_IP}/5672") 2>/dev/null; then
    exec 3<&- 3>&-
    echo "    rabbitmq is up"
    break
  fi
  echo "    attempt ${i}/30: not ready yet, retrying in 2s"
  sleep 2
done

echo ">>> Writing ${APP_DIR}/.env"
cd "${APP_DIR}"
[ -f .env ] || cp .env.example .env
sed -i "s#^BACKEND_INTERNAL_BASE_URL=.*#BACKEND_INTERNAL_BASE_URL=http://${BACKEND_IP}:8000#" .env
sed -i "s#^RABBITMQ_URL=.*#RABBITMQ_URL=amqp://${RABBITMQ_USER}:${RABBITMQ_PASS}@${RABBITMQ_IP}:5672/#" .env

echo ">>> Starting fetcher-service"
docker compose up -d --build

echo ">>> Provisioning complete"
echo "    Fetcher Service reachable at 192.168.0.222:8002 on the LAN"
