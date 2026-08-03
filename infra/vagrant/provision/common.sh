#!/usr/bin/env bash
set -euo pipefail

managed_hosts="$1"

export DEBIAN_FRONTEND=noninteractive
apt_get() { apt-get -o DPkg::Lock::Timeout=300 "$@"; }

systemctl disable --now apt-daily.timer apt-daily-upgrade.timer >/dev/null 2>&1 || true
systemctl stop apt-daily.service apt-daily-upgrade.service unattended-upgrades.service >/dev/null 2>&1 || true

for attempt in {1..150}; do
  if ! fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then
    break
  fi

  if [[ "${attempt}" -eq 150 ]]; then
    echo "dpkg lock was not released within 5 minutes" >&2
    fuser -v /var/lib/dpkg/lock-frontend >&2 || true
    exit 1
  fi

  sleep 2
done

sed -i '/# rateboard-vagrant-begin/,/# rateboard-vagrant-end/d' /etc/hosts
{
  echo '# rateboard-vagrant-begin'
  printf '%b\n' "${managed_hosts}"
  echo '# rateboard-vagrant-end'
} >> /etc/hosts

apt_get update -qq
apt_get install -y --no-install-recommends ca-certificates curl gnupg openssh-server

install -m 0755 -d /etc/apt/keyrings
if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
  curl --fail --location --retry 3 https://download.docker.com/linux/ubuntu/gpg |
    gpg --dearmor --yes --output /etc/apt/keyrings/docker.gpg
  chmod 0644 /etc/apt/keyrings/docker.gpg
fi
architecture="$(dpkg --print-architecture)"
codename="$(. /etc/os-release && printf '%s' "${VERSION_CODENAME}")"
echo "deb [arch=${architecture} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${codename} stable" \
  > /etc/apt/sources.list.d/docker.list
apt_get update -qq
apt_get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
usermod -aG docker vagrant
docker version >/dev/null
docker compose version >/dev/null

# Expose SSH on both the Vagrant NAT adapter and the bridged LAN adapter.
# Authentication still requires an authorized SSH key; root/password login is
# not enabled.
install -d -m 0755 /etc/ssh/sshd_config.d
{
  echo 'AddressFamily any'
  echo 'ListenAddress 0.0.0.0'
  echo 'PubkeyAuthentication yes'
  echo 'PasswordAuthentication no'
  echo 'PermitRootLogin no'
} > /etc/ssh/sshd_config.d/99-rateboard-lan.conf
/usr/sbin/sshd -t
systemctl enable ssh
systemctl restart ssh

if command -v ufw >/dev/null 2>&1; then
  ufw --force disable >/dev/null
  ufw --force reset >/dev/null
fi

if [[ ! -f /swapfile ]]; then
  fallocate -l 512M /swapfile
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
fi
swapon --show=NAME --noheadings | grep -qx /swapfile || swapon /swapfile
grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab

install -d -m 0755 /opt/rateboard /etc/rateboard
