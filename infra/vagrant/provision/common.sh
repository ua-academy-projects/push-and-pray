#!/usr/bin/env bash
set -euo pipefail

managed_hosts="$1"
ssh_username="$2"

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
apt_get install -y --no-install-recommends ca-certificates curl gnupg openssh-server sudo

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

if ! getent group "${ssh_username}" >/dev/null 2>&1; then
  groupadd "${ssh_username}"
fi
if ! id -u "${ssh_username}" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash --gid "${ssh_username}" "${ssh_username}"
fi
usermod --shell /bin/bash --append --groups sudo,docker "${ssh_username}"
passwd --lock "${ssh_username}" >/dev/null 2>&1 || true

printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\n' "${ssh_username}" \
  > "/etc/sudoers.d/90-rateboard-${ssh_username}"
chmod 0440 "/etc/sudoers.d/90-rateboard-${ssh_username}"
visudo -cf "/etc/sudoers.d/90-rateboard-${ssh_username}" >/dev/null

ssh_home="$(getent passwd "${ssh_username}" | cut -d: -f6)"
install -d -m 0700 -o "${ssh_username}" -g "${ssh_username}" "${ssh_home}/.ssh"
authorized_keys="${ssh_home}/.ssh/authorized_keys"
temporary_keys="$(mktemp)"
trap 'rm -f "${temporary_keys}"' EXIT
if [[ -f "${authorized_keys}" ]]; then
  awk '
    $0 == "# rateboard-managed-begin" { managed = 1; next }
    $0 == "# rateboard-managed-end" { managed = 0; next }
    !managed { print }
  ' "${authorized_keys}" > "${temporary_keys}"
fi
{
  echo '# rateboard-managed-begin'
  cat /tmp/rateboard-authorized-keys
  echo '# rateboard-managed-end'
} >> "${temporary_keys}"
install -m 0600 -o "${ssh_username}" -g "${ssh_username}" "${temporary_keys}" "${authorized_keys}"
rm -f /tmp/rateboard-authorized-keys

install -d -m 0755 /opt/rateboard /etc/rateboard
install -m 0600 -o root -g root /tmp/rateboard-alloy.env /etc/rateboard/alloy.env
install -m 0644 -o root -g root /tmp/rateboard-logs-ca.crt /etc/rateboard/logs-ca.crt
rm -f /tmp/rateboard-alloy.env /tmp/rateboard-logs-ca.crt

install -d -m 0755 /var/log/journal /etc/systemd/journald.conf.d
{
  echo '[Journal]'
  echo 'Storage=persistent'
  echo 'SystemMaxUse=128M'
  echo 'RuntimeMaxUse=64M'
  echo 'Compress=yes'
} > /etc/systemd/journald.conf.d/60-rateboard.conf
systemctl restart systemd-journald
journalctl --flush >/dev/null 2>&1 || true

# Expose SSH on both the Vagrant NAT adapter and the bridged LAN adapter.
# Authentication still requires an authorized SSH key; root/password login is
# not enabled.
install -d -m 0755 /etc/ssh/sshd_config.d
{
  echo 'AddressFamily any'
  echo 'ListenAddress 0.0.0.0'
  echo 'PubkeyAuthentication yes'
  echo 'PasswordAuthentication no'
  echo 'KbdInteractiveAuthentication no'
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
