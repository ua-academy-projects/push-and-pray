#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

SSH_USER="weather"

log() {
    printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

log "Installing base networking tools"

apt-get update

apt-get install -y \
    avahi-daemon \
    libnss-mdns \
    ca-certificates \
    curl \
    gnupg \
    jq \
    rsync \
    iproute2 \
    dnsutils

systemctl enable avahi-daemon
systemctl restart avahi-daemon

log "Creating the ${SSH_USER} SSH user"

if ! id "${SSH_USER}" >/dev/null 2>&1; then
    useradd --create-home --shell /bin/bash "${SSH_USER}"
fi

usermod -aG sudo,docker "${SSH_USER}" 2>/dev/null || usermod -aG sudo "${SSH_USER}"
passwd --lock "${SSH_USER}" >/dev/null 2>&1 || true

install -d -m 0700 -o "${SSH_USER}" -g "${SSH_USER}" "/home/${SSH_USER}/.ssh"
install -m 0600 -o "${SSH_USER}" -g "${SSH_USER}" \
    /home/vagrant/.ssh/authorized_keys \
    "/home/${SSH_USER}/.ssh/authorized_keys"

cat > "/etc/sudoers.d/${SSH_USER}" <<EOF
${SSH_USER} ALL=(ALL) NOPASSWD:ALL
EOF
chmod 0440 "/etc/sudoers.d/${SSH_USER}"


log "Installing Docker Engine and Docker Compose plugin by provisioning script"

install -m 0755 -d /etc/apt/keyrings

if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        -o /etc/apt/keyrings/docker.asc
fi

chmod a+r /etc/apt/keyrings/docker.asc

. /etc/os-release

cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable
EOF

apt-get update

apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

systemctl enable docker
systemctl restart docker

usermod -aG docker vagrant
usermod -aG docker "${SSH_USER}"

install -d -m 0755 \
    /etc/weatherflow \
    /opt/weatherflow \
    /usr/local/lib/weatherflow


cat > /usr/local/lib/weatherflow/network.sh <<'LIB'
#!/usr/bin/env bash
set -euo pipefail

resolve_lan_host() {
    local hostname="$1"
    local attempts="${2:-120}"
    local delay="${3:-3}"
    local address=""

    for ((attempt = 1; attempt <= attempts; attempt++)); do
        address="$(
            getent ahostsv4 "$hostname" 2>/dev/null |
            awk '{print $1}' |
            grep -Ev '^(127\.|10\.0\.2\.15$)' |
            sort -u |
            head -n 1 || true
        )"

        if [[ -n "$address" ]]; then
            printf '%s\n' "$address"
            return 0
        fi

        sleep "$delay"
    done

    echo "Could not resolve bridged LAN host: $hostname" >&2
    return 1
}
LIB

chmod 0755 /usr/local/lib/weatherflow/network.sh


log "Verifying that this VM has a real bridged LAN address"

LAN_RECORD=""

for _ in $(seq 1 60); do
    LAN_RECORD="$(
        ip -4 -o addr show scope global |
        awk '
            $2 !~ /^(lo|docker|br-|veth)/ &&
            $4 !~ /^10\.0\.2\.15\// &&
            !found {
                print $2 " " $4
                found = 1
            }
        '
    )"

    if [[ -n "$LAN_RECORD" ]]; then
        break
    fi

    sleep 2
done


if [[ -z "$LAN_RECORD" ]]; then
    cat >&2 <<'ERROR'
ERROR: No bridged LAN address was detected.
The VM only has the Vagrant NAT address or no second adapter.

Select a physical Wi-Fi/Ethernet adapter for public_network and run:

  vagrant destroy -f
  vagrant up

Do not select VirtualBox Host-Only Adapter.
ERROR

    exit 1
fi


LAN_INTERFACE="${LAN_RECORD%% *}"
LAN_CIDR="${LAN_RECORD#* }"
LAN_IP="${LAN_CIDR%%/*}"
LAN_PREFIX="${LAN_CIDR#*/}"

LAN_NETWORK="$(
    ip -4 route show \
        dev "$LAN_INTERFACE" \
        proto kernel \
        scope link |
    awk 'NR == 1 {print $1}'
)"


if [[ -z "$LAN_INTERFACE" ]]; then
    echo "ERROR: LAN interface was not detected." >&2
    exit 1
fi

if [[ -z "$LAN_IP" ]]; then
    echo "ERROR: LAN IP address was not detected." >&2
    exit 1
fi

if [[ -z "$LAN_NETWORK" ]]; then
    echo "ERROR: LAN network was not detected for interface ${LAN_INTERFACE}." >&2
    exit 1
fi


LAN_HOSTNAME="$(hostname).local"


cat > /etc/weatherflow/lan.env <<EOF
LAN_INTERFACE=${LAN_INTERFACE}
LAN_IP=${LAN_IP}
LAN_PREFIX=${LAN_PREFIX}
LAN_NETWORK=${LAN_NETWORK}
LAN_HOSTNAME=${LAN_HOSTNAME}
EOF

chmod 0644 /etc/weatherflow/lan.env


cat > /usr/local/bin/weatherflow-lan-info <<'INFO'
#!/usr/bin/env bash
set -euo pipefail

source /etc/weatherflow/lan.env

cat <<EOF
BRIDGED LAN VERIFIED
VM hostname : $(hostname)
LAN name    : ${LAN_HOSTNAME}
LAN adapter : ${LAN_INTERFACE}
LAN network : ${LAN_NETWORK}
LAN address : ${LAN_IP}/${LAN_PREFIX}
Docker      : $(docker --version)
Compose     : $(docker compose version)
EOF
INFO

chmod 0755 /usr/local/bin/weatherflow-lan-info

/usr/local/bin/weatherflow-lan-info
