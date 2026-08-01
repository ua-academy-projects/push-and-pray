#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

readonly APP_ROOT="/opt/weather-app"

log() {
    printf '\n[weather-app] %s\n' "$*"
}

install_packages() {
    apt-get install -y --no-install-recommends "$@"
}

install_docker() {
    if command -v docker >/dev/null 2>&1 \
        && docker compose version >/dev/null 2>&1; then

        log "Docker and Docker Compose are already installed"

        systemctl enable --now docker

        return 0
    fi

    log "Installing Docker Engine and Docker Compose plugin"

    apt-get update

    install_packages \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    install -m 0755 -d /etc/apt/keyrings

    if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
        curl -fsSL \
            https://download.docker.com/linux/ubuntu/gpg \
            -o /etc/apt/keyrings/docker.asc

        chmod a+r /etc/apt/keyrings/docker.asc
    fi

    local arch
    arch="$(dpkg --print-architecture)"

    local codename
    codename="$(lsb_release -cs 2>/dev/null || echo "noble")"

    echo \
        "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${codename} stable" \
        > /etc/apt/sources.list.d/docker.list

    apt-get update

    install_packages \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    systemctl enable --now docker

    if getent group docker >/dev/null 2>&1; then
        usermod -aG docker vagrant
    fi
}

configure_local_name_resolution() {
    log "Configuring local VM name resolution"

    install_packages \
        avahi-daemon \
        libnss-mdns

    systemctl enable --now avahi-daemon
    systemctl restart avahi-daemon

    if ! grep -q "mdns4_minimal" /etc/nsswitch.conf; then
        sed -i \
            's/^hosts:.*/hosts:          files mdns4_minimal [NOTFOUND=return] dns mdns4/' \
            /etc/nsswitch.conf
    fi

    if command -v ufw >/dev/null 2>&1 \
        && ufw status | grep -q "Status: active"; then

        ufw allow 5353/udp || true
    fi
}

resolve_vm_ipv4() {
    local hostname="$1"
    local attempt
    local address

    for attempt in $(seq 1 60); do
        address="$(
            getent ahostsv4 "${hostname}" \
                | awk '
                    $1 !~ /^127\./ &&
                    $1 !~ /^169\.254\./ {
                        print $1
                        exit
                    }
                '
        )"

        if [[ -n "${address}" ]]; then
            printf '%s\n' "${address}"
            return 0
        fi

        sleep 2
    done

    log "Could not resolve ${hostname} in the local network"

    return 1
}

setup_custom_user() {
    local username="${HOST_USER:-}"
    local ssh_key="${HOST_SSH_KEY:-}"

    if [[ -z "${username}" ]]; then
        log "HOST_USER is not set; skipping custom user setup"
        return 0
    fi

    if [[ "${username}" == "vagrant" || "${username}" == "root" ]]; then
        log "Custom user matches default user '${username}'; skipping creation"
        return 0
    fi

    log "Configuring custom Linux user: ${username}"

    # 1. Створення користувача через adduser (якщо не існує)
    if id "${username}" >/dev/null 2>&1; then
        log "User '${username}' already exists"
    else
        log "Creating user '${username}'"
        adduser --disabled-password --gecos "" "${username}"
    fi

    # 2. Перевірка наявності та додавання до груп sudo і docker
    if getent group sudo >/dev/null 2>&1; then
        usermod -aG sudo "${username}"
    fi

    if getent group docker >/dev/null 2>&1; then
        usermod -aG docker "${username}"
    fi

    # 3. Налаштування SSH директорії та ключа
    if [[ -n "${ssh_key}" ]]; then
        local user_home
        user_home="$(getent passwd "${username}" | cut -d: -f6)"
        if [[ -z "${user_home}" ]]; then
            user_home="/home/${username}"
        fi

        local ssh_dir="${user_home}/.ssh"
        local auth_keys="${ssh_dir}/authorized_keys"

        log "Setting up SSH key for '${username}'"

        mkdir -p "${ssh_dir}"
        chmod 0700 "${ssh_dir}"

        touch "${auth_keys}"
        chmod 0600 "${auth_keys}"

        if grep -qxF "${ssh_key}" "${auth_keys}"; then
            log "SSH public key already present in ${auth_keys}"
        else
            log "Adding SSH public key to ${auth_keys}"
            echo "${ssh_key}" >> "${auth_keys}"
        fi

        # Зміна власника лише для конкретних файлів і директорій (без chown -R)
        chown "${username}:${username}" "${user_home}"
        chown "${username}:${username}" "${ssh_dir}"
        chown "${username}:${username}" "${auth_keys}"
    else
        log "HOST_SSH_KEY is empty; skipping SSH key setup for '${username}'"
    fi
}

configure_common_system() {
    log "Updating package metadata"

    apt-get update

    log "Installing common system packages"

    install_packages \
        ca-certificates \
        curl

    install -d "${APP_ROOT}"

    configure_local_name_resolution
    install_docker
    setup_custom_user
}