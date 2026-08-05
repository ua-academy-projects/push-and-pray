#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get -o DPkg::Lock::Timeout=300 update -qq
apt-get -o DPkg::Lock::Timeout=300 install -y --no-install-recommends e2fsprogs openssl

# shellcheck disable=SC1091
source /tmp/rateboard.env
install -m 0600 -o root -g root /tmp/rateboard.env /etc/rateboard/logs.env
rm -f /tmp/rateboard.env

logs_device_link="/dev/disk/by-id/virtio-rateboard-logsdata"
for attempt in {1..30}; do
  [[ -b "${logs_device_link}" ]] && break
  if [[ "${attempt}" -eq 30 ]]; then
    echo "Persistent logs disk ${logs_device_link} was not attached." >&2
    lsblk -o NAME,PATH,SIZE,FSTYPE,LABEL,MOUNTPOINTS >&2
    exit 1
  fi
  sleep 1
done

logs_device="$(readlink -f "${logs_device_link}")"
root_device="$(findmnt -n -o SOURCE /)"
if [[ "${root_device}" == "${logs_device}"* ]]; then
  echo "Refusing to format root device ${logs_device}." >&2
  exit 1
fi

filesystem_type="$(blkid -s TYPE -o value "${logs_device}" 2>/dev/null || true)"
if [[ -z "${filesystem_type}" ]]; then
  mkfs.ext4 -F -L rateboard-logs "${logs_device}"
elif [[ "${filesystem_type}" != ext4 ]]; then
  echo "Refusing to overwrite ${logs_device}: expected ext4 or a blank disk, found ${filesystem_type}." >&2
  exit 1
fi

logs_uuid="$(blkid -s UUID -o value "${logs_device}")"
[[ -n "${logs_uuid}" ]] || { echo "Persistent logs disk has no filesystem UUID." >&2; exit 1; }
install -d -m 0755 /srv/rateboard-logs
sed -i '\|[[:space:]]/srv/rateboard-logs[[:space:]]|d' /etc/fstab
printf 'UUID=%s /srv/rateboard-logs ext4 defaults,nofail 0 2\n' "${logs_uuid}" >> /etc/fstab
mountpoint -q /srv/rateboard-logs || mount /srv/rateboard-logs

install -d -m 0750 -o 10001 -g 10001 /srv/rateboard-logs/loki
install -d -m 0750 -o 472 -g 472 /srv/rateboard-logs/grafana
install -d -m 0750 -o 473 -g 473 /srv/rateboard-logs/alloy

install -d -m 0700 /etc/rateboard/logs/tls
install -m 0644 -o root -g root /tmp/rateboard-logs-server.crt /etc/rateboard/logs/tls/server.crt
install -m 0600 -o root -g root /tmp/rateboard-logs-server.key /etc/rateboard/logs/tls/server.key
rm -f /tmp/rateboard-logs-server.crt /tmp/rateboard-logs-server.key

password_hash="$(printf '%s\n' "${RATEBOARD_LOGS_INGEST_PASSWORD}" | openssl passwd -apr1 -stdin)"
printf '%s:%s\n' "${RATEBOARD_LOGS_INGEST_USER}" "${password_hash}" > /etc/rateboard/logs/htpasswd
# nginx:1.27.5-alpine runs workers as UID/GID 101. The bind-mounted file must
# remain private while being readable by those workers for auth_basic.
chown root:101 /etc/rateboard/logs/htpasswd
chmod 0640 /etc/rateboard/logs/htpasswd

compose=(
  docker compose
  --env-file /etc/rateboard/logs.env
  --env-file /etc/rateboard/alloy.env
  --file /vagrant/infra/docker/logs/compose.yml
)
"${compose[@]}" up --detach --force-recreate --remove-orphans

for attempt in {1..60}; do
  if curl --fail --silent --show-error --cacert /etc/rateboard/logs-ca.crt \
    --resolve rates-logs:443:127.0.0.1 https://rates-logs/api/health >/dev/null 2>&1 && \
     curl --fail --silent --show-error --cacert /etc/rateboard/logs-ca.crt \
    --resolve rates-logs:443:127.0.0.1 https://rates-logs/loki-ready >/dev/null 2>&1; then
    exit 0
  fi
  if [[ "${attempt}" -eq 60 ]]; then
    "${compose[@]}" ps >&2
    "${compose[@]}" logs --tail=100 >&2
    exit 1
  fi
  sleep 2
done
