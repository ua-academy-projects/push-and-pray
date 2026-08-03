#!/usr/bin/env bash
set -euo pipefail

install -m 0600 -o root -g root /tmp/rateboard.env /etc/rateboard/database.env
rm -f /tmp/rateboard.env

systemctl disable --now postgresql 2>/dev/null || true
export DEBIAN_FRONTEND=noninteractive
apt-get -o DPkg::Lock::Timeout=300 update -qq
apt-get -o DPkg::Lock::Timeout=300 install -y --no-install-recommends e2fsprogs

database_device_link="/dev/disk/by-id/virtio-rateboard-pgdata"
for attempt in {1..30}; do
  [[ -b "${database_device_link}" ]] && break
  if [[ "${attempt}" -eq 30 ]]; then
    echo "Persistent PostgreSQL disk ${database_device_link} was not attached." >&2
    lsblk -o NAME,PATH,SIZE,FSTYPE,LABEL,MOUNTPOINTS >&2
    exit 1
  fi
  sleep 1
done

database_device="$(readlink -f "${database_device_link}")"
root_device="$(findmnt -n -o SOURCE /)"
if [[ "${root_device}" == "${database_device}"* ]]; then
  echo "Refusing to format root device ${database_device}." >&2
  exit 1
fi

filesystem_type="$(blkid -s TYPE -o value "${database_device}" 2>/dev/null || true)"
if [[ -z "${filesystem_type}" ]]; then
  mkfs.ext4 -F -L rateboard-pgdata "${database_device}"
elif [[ "${filesystem_type}" != "ext4" ]]; then
  echo "Refusing to overwrite ${database_device}: expected ext4 or a blank disk, found ${filesystem_type}." >&2
  lsblk -o NAME,PATH,SIZE,FSTYPE,LABEL,MOUNTPOINTS "${database_device}" >&2
  exit 1
fi

install -d -m 0755 /srv/rateboard-data
database_uuid="$(blkid -s UUID -o value "${database_device}")"
if [[ -z "${database_uuid}" ]]; then
  echo "Persistent PostgreSQL disk ${database_device} has no filesystem UUID." >&2
  exit 1
fi

# Replace a stale entry left by an older provisioner that assumed /dev/vdb.
sed -i '\|[[:space:]]/srv/rateboard-data[[:space:]]|d' /etc/fstab
printf 'UUID=%s /srv/rateboard-data ext4 defaults,nofail 0 2\n' "${database_uuid}" >> /etc/fstab
mountpoint -q /srv/rateboard-data || mount /srv/rateboard-data
install -d -m 0700 -o 999 -g 999 /srv/rateboard-data/postgresql

compose=(docker compose --env-file /etc/rateboard/database.env --file /vagrant/infra/docker/database/compose.yml)
"${compose[@]}" up --detach postgres

for attempt in {1..60}; do
  if "${compose[@]}" exec -T postgres pg_isready -U rates -d rates >/dev/null 2>&1; then
    break
  fi
  if [[ "${attempt}" -eq 60 ]]; then
    "${compose[@]}" logs --tail=100 postgres >&2
    exit 1
  fi
  sleep 2
done

"${compose[@]}" --profile tools run --rm migrate
