#!/usr/bin/env bash
set -euo pipefail

readonly ROLE="${1:-}"
readonly PRIVATE_NETWORK="192.168.100.0/24"
readonly UI_ADDRESS="192.168.100.10"
readonly HISTORY_ADDRESS="192.168.100.11"
readonly PROVIDER_ADDRESS="192.168.100.12"
readonly INFRASTRUCTURE_ADDRESS="192.168.100.14"

fail() {
  echo "Aegis firewall provisioning failed: $*" >&2
  exit 1
}

case "${ROLE}" in
  ui|history|provider|infra)
    ;;
  *)
    fail "unsupported firewall role '${ROLE}'"
    ;;
esac

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install --yes --no-install-recommends ufw

# Preserve Vagrant management before changing the default inbound policy.
ufw allow 22/tcp comment "Vagrant SSH"
ufw default deny incoming
ufw default allow outgoing

case "${ROLE}" in
  ui)
    ufw allow from "${PRIVATE_NETWORK}" to any port 8000 proto tcp \
      comment "Aegis UI from deployment network"
    ufw allow from "${PRIVATE_NETWORK}" to any port 8002 proto tcp \
      comment "Aegis History from network"
    ufw deny out to "${PROVIDER_ADDRESS}" port 8001 proto tcp \
      comment "Block UI direct Provider access"
    ufw deny out to "${INFRASTRUCTURE_ADDRESS}" port 3306 proto tcp \
      comment "Block UI database access"
    ;;
  history)
    ufw allow from "${UI_ADDRESS}" to any port 8002 proto tcp \
      comment "Aegis History from UI"
    ufw allow from "${HISTORY_ADDRESS}" to any port 8002 proto tcp \
      comment "History local health checks"
    ;;
  provider)
    ufw allow from "${HISTORY_ADDRESS}" to any port 8001 proto tcp \
      comment "Aegis Provider from History"
    ufw allow from "${PROVIDER_ADDRESS}" to any port 8001 proto tcp \
      comment "Provider local health checks"
    ufw deny out to "${INFRASTRUCTURE_ADDRESS}" port 3306 proto tcp \
      comment "Block Provider database access"
    ufw deny out to "${UI_ADDRESS}" port 8000 proto tcp \
      comment "Block Provider UI access"
    ;;
  infra)
    ufw allow from "${HISTORY_ADDRESS}" to any port 3306 proto tcp \
      comment "MariaDB from History"
    ufw allow from "${PROVIDER_ADDRESS}" to any port 5672 proto tcp \
      comment "RabbitMQ publisher from Provider"
    ufw allow from "${HISTORY_ADDRESS}" to any port 5672 proto tcp \
      comment "RabbitMQ consumer from History"
    ufw allow from "${PRIVATE_NETWORK}" to any port 15672 proto tcp \
      comment "RabbitMQ management on the private network"
    ufw allow from "${UI_ADDRESS}" to any port 6379 proto tcp \
      comment "Redis theme state from UI"
    ;;
esac

ufw --force enable
ufw status verbose
