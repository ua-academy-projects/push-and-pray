#!/usr/bin/env bash
# Provisions the postgres VM: installs Docker Engine + the Compose plugin, writes
# this stack's .env, and runs `docker compose up -d --build` against the
# infra/postgres compose project synced to /app (Postgres + Redis + RabbitMQ, each
# its own container -- see infra/postgres/docker-compose.yml). Safe to re-run.
#
# Networking note: all VMs are bridged onto the host's LAN (see Vagrantfile), each
# with its own fixed IP. Every container in the compose project uses
# network_mode: host, so it binds directly to this VM's bridged interface at its
# usual port -- no NAT/port-mapping trick needed, and nothing changes for the
# backend-service/fetcher-service VMs that connect to it.
set -euo pipefail

APP_DIR="/app"
DB_USER="skyivano"
DB_PASS="skyivano"
DB_NAME="skyivano"
DB_TEST_NAME="skyivano_test"
REDIS_PASS="skyivano"
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

echo ">>> Writing ${APP_DIR}/.env"
cd "${APP_DIR}"
[ -f .env ] || cp .env.example .env
sed -i "s#^POSTGRES_USER=.*#POSTGRES_USER=${DB_USER}#" .env
sed -i "s#^POSTGRES_PASSWORD=.*#POSTGRES_PASSWORD=${DB_PASS}#" .env
sed -i "s#^POSTGRES_DB=.*#POSTGRES_DB=${DB_NAME}#" .env
sed -i "s#^POSTGRES_TEST_DB=.*#POSTGRES_TEST_DB=${DB_TEST_NAME}#" .env
sed -i "s#^REDIS_PASSWORD=.*#REDIS_PASSWORD=${REDIS_PASS}#" .env
sed -i "s#^RABBITMQ_DEFAULT_USER=.*#RABBITMQ_DEFAULT_USER=${RABBITMQ_USER}#" .env
sed -i "s#^RABBITMQ_DEFAULT_PASS=.*#RABBITMQ_DEFAULT_PASS=${RABBITMQ_PASS}#" .env

echo ">>> Starting the postgres/redis/rabbitmq stack"
docker compose up -d --build

echo ">>> Provisioning complete"
echo "    Postgres reachable at 192.168.0.220:5432 on the LAN (user=${DB_USER} db=${DB_NAME}/${DB_TEST_NAME})"
echo "    Redis reachable at 192.168.0.220:6379 on the LAN (UI session state only, password required)"
echo "    RabbitMQ reachable at 192.168.0.220:5672 on the LAN (user=${RABBITMQ_USER}), management UI at :15672"
