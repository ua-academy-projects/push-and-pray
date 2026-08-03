#!/usr/bin/env bash
set -Eeuo pipefail

log() {
    printf '\n[%s] %s\n' "$(date --iso-8601=seconds)" "$*"
}

retry() {
    local attempts="$1"
    local delay="$2"
    shift 2

    local attempt=1

    until "$@"; do
        if (( attempt >= attempts )); then
            log "Command failed after ${attempts} attempts: $*"
            return 1
        fi

        log "Attempt ${attempt}/${attempts} failed. Retrying..."
        sleep "${delay}"
        ((attempt += 1))
    done
}

required_variables=(
    AIRAWARE_ROLE
    AIRAWARE_VM_IP
    AIRAWARE_HOSTNAME
    AIRAWARE_FRONTEND_IP
    AIRAWARE_BACKEND_IP
    AIRAWARE_FETCHER_IP
    AIRAWARE_DATABASE_IP
)

for variable_name in "${required_variables[@]}"; do
    if [[ -z "${!variable_name:-}" ]]; then
        echo "Required variable is missing: ${variable_name}" >&2
        exit 1
    fi
done

log "Provisioning common configuration"
log "Role: ${AIRAWARE_ROLE}"
log "Hostname: ${AIRAWARE_HOSTNAME}"
log "LAN address: ${AIRAWARE_VM_IP}"

export DEBIAN_FRONTEND=noninteractive

retry 5 10 apt-get update

apt-get install -y \
    ca-certificates \
    curl \
    dnsutils \
    iputils-ping \
    jq \
    net-tools \
    python3 \
    rsync \
    traceroute

if ! id airaware >/dev/null 2>&1; then
    useradd \
        --system \
        --home-dir /opt/airaware \
        --create-home \
        --shell /usr/sbin/nologin \
        airaware
fi

install -d \
    -o airaware \
    -g airaware \
    -m 0755 \
    /opt/airaware

cat >/etc/airaware-machine.conf <<EOF
ROLE=${AIRAWARE_ROLE}
HOSTNAME=${AIRAWARE_HOSTNAME}
LAN_IP=${AIRAWARE_VM_IP}
EOF

chmod 0644 /etc/airaware-machine.conf

# Keep the block idempotent when provision runs more than once.
sed -i \
    '/# BEGIN AIRAWARE HOSTS/,/# END AIRAWARE HOSTS/d' \
    /etc/hosts

cat >>/etc/hosts <<EOF
# BEGIN AIRAWARE HOSTS
${AIRAWARE_FRONTEND_IP} airaware-frontend frontend
${AIRAWARE_BACKEND_IP} airaware-backend backend
${AIRAWARE_FETCHER_IP} airaware-fetcher fetcher
${AIRAWARE_DATABASE_IP} airaware-database database
# END AIRAWARE HOSTS
EOF

cat >/etc/motd <<EOF
AirAware Vagrant VM

Role:     ${AIRAWARE_ROLE}
Hostname: ${AIRAWARE_HOSTNAME}
LAN IP:   ${AIRAWARE_VM_IP}
EOF

log "Network interfaces"
ip -br address

log "Routing table"
ip route

log "Common provisioning completed"
