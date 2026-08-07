#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:-}"
PROJECT_ROOT="${PROJECT_ROOT:-/vagrant}"
CONFIG_FILE="${PROJECT_ROOT}/deploy.env"
COMPOSE_FILE="${PROJECT_ROOT}/compose/${ROLE}/compose.yaml"
BACKEND_CONTAINER_SUBNET="172.29.0.0/24"
VM_ADMIN_USER="${VM_ADMIN_USER:-wildlife}"
LOG_READER_USER="wildlife-log-reader"

if [ "$(id -u)" -ne 0 ]; then
    echo "Run this provisioning script with sudo." >&2
    exit 1
fi

case "$ROLE" in
    database|redis|fetcher|backend|ui|logging)
        ;;
    *)
        echo "Unknown container node role: ${ROLE}" >&2
        exit 2
        ;;
esac

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Create deploy.env from deploy.env.example first." >&2
    exit 1
fi

set -a
# shellcheck disable=SC1090
source "$CONFIG_FILE"
set +a

if ! [[ "$VM_ADMIN_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    echo "Invalid VM_ADMIN_USER: ${VM_ADMIN_USER}" >&2
    exit 2
fi


sync_clock() {
    timedatectl set-ntp true || true
    systemctl restart systemd-timesyncd.service || true

    for _attempt in {1..20}; do
        if timedatectl show \
            --property=NTPSynchronized \
            --value \
            | grep -Fxq "yes"; then
            return 0
        fi
        sleep 2
    done

    echo "Warning: NTP synchronization was not confirmed." >&2
}


disable_old_runtime() {
    local unit
    for unit in \
        wildlife-backend.service \
        wildlife-ui.service \
        wildlife-fetcher.service \
        wildlife-fetcher.timer \
        postgresql.service \
        redis-server.service \
        rabbitmq-server.service; do
        if systemctl cat "$unit" >/dev/null 2>&1; then
            systemctl disable --now "$unit" || true
        fi
    done
}


install_docker_compose() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y docker.io ca-certificates curl iptables

    if apt-cache show docker-compose-v2 >/dev/null 2>&1; then
        apt-get install -y docker-compose-v2
    else
        apt-get install -y docker-compose
    fi

    systemctl enable --now docker.service
    if id vagrant >/dev/null 2>&1; then
        usermod -aG docker vagrant
    fi
}


enable_persistent_journal() {
    install -d -m 0755 /var/log/journal /etc/systemd/journald.conf.d
    cat > /etc/systemd/journald.conf.d/wildlife.conf <<'EOF'
[Journal]
Storage=persistent
Compress=yes
SystemMaxUse=500M
RuntimeMaxUse=100M
MaxRetentionSec=7day
EOF
    systemd-tmpfiles --create --prefix /var/log/journal
    systemctl restart systemd-journald.service
}


install_logging_dependencies() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y openssh-client logrotate util-linux
}


install_ssh_user() {
    local source_login="${SUDO_USER:-vagrant}"
    local source_home
    local source_keys
    local user_home="/home/${VM_ADMIN_USER}"
    local user_group

    if ! id "$source_login" >/dev/null 2>&1; then
        source_login="vagrant"
    fi
    source_home="$(getent passwd "$source_login" | cut -d: -f6)"
    source_keys="${source_home}/.ssh/authorized_keys"

    if ! id "$VM_ADMIN_USER" >/dev/null 2>&1; then
        useradd \
            --create-home \
            --shell /bin/bash \
            "$VM_ADMIN_USER"
    fi

    user_group="$(id -gn "$VM_ADMIN_USER")"
    usermod -aG sudo "$VM_ADMIN_USER"
    if getent group docker >/dev/null 2>&1; then
        usermod -aG docker "$VM_ADMIN_USER"
    fi

    if [ ! -s "$source_keys" ]; then
        echo "Source authorized_keys was not found at ${source_keys}." >&2
        exit 1
    fi

    install -d \
        -m 0700 \
        -o "$VM_ADMIN_USER" \
        -g "$user_group" \
        "${user_home}/.ssh"
    if [ "$source_keys" != "${user_home}/.ssh/authorized_keys" ]; then
        install \
            -m 0600 \
            -o "$VM_ADMIN_USER" \
            -g "$user_group" \
            "$source_keys" \
            "${user_home}/.ssh/authorized_keys"
    else
        chown "$VM_ADMIN_USER:$user_group" "$source_keys"
        chmod 0600 "$source_keys"
    fi

    printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$VM_ADMIN_USER" \
        > "/etc/sudoers.d/90-${VM_ADMIN_USER}"
    chmod 0440 "/etc/sudoers.d/90-${VM_ADMIN_USER}"
    visudo -cf "/etc/sudoers.d/90-${VM_ADMIN_USER}" >/dev/null
}


install_log_collector_access() {
    local public_key_path="${PROJECT_ROOT}/logging/wildlife-log-collector.pub"
    local user_home="/home/${LOG_READER_USER}"
    local authorized_keys="${user_home}/.ssh/authorized_keys"
    local user_group

    if [ ! -s "$public_key_path" ]; then
        echo "Logging collector public key is missing: ${public_key_path}" >&2
        echo "Provision the logging VM before ${ROLE}." >&2
        exit 1
    fi

    if ! id "$LOG_READER_USER" >/dev/null 2>&1; then
        useradd \
            --create-home \
            --shell /bin/bash \
            "$LOG_READER_USER"
    fi
    user_group="$(id -gn "$LOG_READER_USER")"
    usermod -aG systemd-journal "$LOG_READER_USER"
    install -d \
        -m 0700 \
        -o "$LOG_READER_USER" \
        -g "$user_group" \
        "${user_home}/.ssh"
    touch "$authorized_keys"
    sed -i \
        '/^# BEGIN WILDLIFE LOG COLLECTOR$/,/^# END WILDLIFE LOG COLLECTOR$/d' \
        "$authorized_keys"
    {
        echo "# BEGIN WILDLIFE LOG COLLECTOR"
        printf 'restrict '
        cat "$public_key_path"
        echo "# END WILDLIFE LOG COLLECTOR"
    } >> "$authorized_keys"
    chown "$LOG_READER_USER:$user_group" "$authorized_keys"
    chmod 0600 "$authorized_keys"
}


remove_legacy_logging_stack() {
    local service
    local container_ids=()

    if ! command -v docker >/dev/null 2>&1 \
        || ! docker info >/dev/null 2>&1; then
        return 0
    fi

    for service in alloy loki grafana; do
        mapfile -t container_ids < <(
            docker ps -aq \
                --filter "label=com.docker.compose.service=${service}"
        )
        if [ "${#container_ids[@]}" -gt 0 ]; then
            docker rm --force "${container_ids[@]}"
        fi
    done

    docker volume rm \
        wildlife_alloy_data \
        wildlife_loki_data \
        wildlife_grafana_data \
        >/dev/null 2>&1 || true
    docker image rm \
        grafana/alloy:v1.18.0 \
        grafana/loki:3.7.0 \
        grafana/grafana:13.1.0 \
        >/dev/null 2>&1 || true
}


install_log_collector() {
    local state_directory="/var/lib/wildlife-log-collector"
    local log_directory="/var/log/wildlife"
    local key_path="${state_directory}/id_ed25519"
    local public_export="${PROJECT_ROOT}/logging/wildlife-log-collector.pub"

    install -d -m 0700 "$state_directory"
    install -d -m 0750 "$log_directory"

    if [ ! -s "$key_path" ]; then
        ssh-keygen \
            -q \
            -t ed25519 \
            -N "" \
            -C "wildlife-log-collector" \
            -f "$key_path"
    fi
    chmod 0600 "$key_path"
    chmod 0644 "${key_path}.pub"
    install -m 0644 "${key_path}.pub" "$public_export"

    install -m 0755 \
        "${PROJECT_ROOT}/logging/collect-logs.sh" \
        /usr/local/sbin/wildlife-collect-logs

    cat > /etc/wildlife-log-targets <<EOF
database ${DB_HOST}
redis ${REDIS_HOST}
fetcher ${FETCHER_HOST}
backend ${BACKEND_HOST}
ui ${UI_HOST}
EOF
    chmod 0644 /etc/wildlife-log-targets

    cat > /etc/wildlife-log-collector.conf <<EOF
LOG_DIRECTORY=${log_directory}
STATE_DIRECTORY=${state_directory}
TARGETS_FILE=/etc/wildlife-log-targets
SSH_USER=${LOG_READER_USER}
SSH_KEY_PATH=${key_path}
SSH_KNOWN_HOSTS_PATH=${state_directory}/known_hosts
EOF
    chmod 0600 /etc/wildlife-log-collector.conf

    cat > /etc/logrotate.d/wildlife-logs <<'EOF'
/var/log/wildlife/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root adm
}
EOF

    cat > /etc/systemd/system/wildlife-log-collector.service <<'EOF'
[Unit]
Description=Collect journals from Ukraine Wildlife VMs
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/wildlife-collect-logs
Nice=10
EOF

    cat > /etc/systemd/system/wildlife-log-collector.timer <<'EOF'
[Unit]
Description=Collect Ukraine Wildlife logs every two minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=2min
AccuracySec=10s
Unit=wildlife-log-collector.service

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now wildlife-log-collector.timer
}


compose() {
    if docker compose version >/dev/null 2>&1; then
        docker compose \
            --env-file "$CONFIG_FILE" \
            -f "$COMPOSE_FILE" \
            "$@"
    else
        docker-compose \
            --env-file "$CONFIG_FILE" \
            -f "$COMPOSE_FILE" \
            "$@"
    fi
}


wait_http() {
    local url="$1"
    local label="$2"

    for _attempt in {1..60}; do
        if curl --fail --silent "$url" >/dev/null; then
            return 0
        fi
        sleep 2
    done

    echo "${label} is not reachable at ${url}" >&2
    return 1
}


export_ui_ca_certificate() {
    local container_id=""
    local container_certificate="/data/caddy/pki/authorities/local/root.crt"
    local export_directory="${PROJECT_ROOT}/tls"
    local export_path="${export_directory}/wildlife-local-root-ca.crt"
    local temporary_path="/tmp/wildlife-local-root-ca.crt"

    for _attempt in {1..60}; do
        container_id="$(compose ps -q caddy)"
        if [ -n "$container_id" ] \
            && docker exec "$container_id" \
                test -s "$container_certificate"; then
            docker cp \
                "${container_id}:${container_certificate}" \
                "$temporary_path"
            install -d -m 0755 "$export_directory"
            install -m 0644 "$temporary_path" "$export_path"
            rm -f "$temporary_path"
            echo "Local CA certificate exported to ${export_path}"
            return 0
        fi
        sleep 2
    done

    echo "Caddy local CA certificate was not created." >&2
    return 1
}


wait_https() {
    local url="$1"
    local certificate="$2"
    local label="$3"

    for _attempt in {1..60}; do
        if curl \
            --cacert "$certificate" \
            --fail \
            --silent \
            "$url" >/dev/null; then
            return 0
        fi
        sleep 2
    done

    echo "${label} is not reachable at ${url}" >&2
    return 1
}


install_fetcher_timer() {
    cat > /etc/systemd/system/wildlife-fetcher-refresh.service <<EOF
[Unit]
Description=Publish Ukraine Wildlife six-month refresh job
After=docker.service network-online.target
Requires=docker.service
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=oneshot
ExecStart=/usr/bin/curl --fail --silent --show-error \\
    --request POST \\
    --header "X-Internal-Service-Token: ${INTERNAL_SERVICE_TOKEN}" \\
    http://${FETCHER_HOST}:8002/internal/publish-refresh
Restart=on-failure
RestartSec=15min
TimeoutStartSec=20min
EOF

    cat > /etc/systemd/system/wildlife-fetcher-refresh.timer <<'EOF'
[Unit]
Description=Trigger wildlife refresh every six months

[Timer]
OnCalendar=*-01-01 03:00:00
OnCalendar=*-07-01 03:00:00
Persistent=true
Unit=wildlife-fetcher-refresh.service

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now wildlife-fetcher-refresh.timer
}


install_backend_egress_filter() {
    cat > /usr/local/sbin/wildlife-backend-egress <<EOF
#!/usr/bin/env bash
set -euo pipefail

CHAIN="WILDLIFE-BACKEND"
SUBNET="${BACKEND_CONTAINER_SUBNET}"
LAN="${LAN_CIDR}"

iptables -N "\$CHAIN" 2>/dev/null || true
iptables -F "\$CHAIN"
iptables -A "\$CHAIN" \\
    -m conntrack --ctstate ESTABLISHED,RELATED \\
    -j ACCEPT
iptables -A "\$CHAIN" -d "\$SUBNET" -j ACCEPT
iptables -A "\$CHAIN" -d "\$LAN" -j ACCEPT
iptables -A "\$CHAIN" -j REJECT

if ! iptables -C DOCKER-USER -s "\$SUBNET" -j "\$CHAIN" 2>/dev/null; then
    iptables -I DOCKER-USER 1 -s "\$SUBNET" -j "\$CHAIN"
fi
EOF
    chmod 0755 /usr/local/sbin/wildlife-backend-egress

    cat > /etc/systemd/system/wildlife-backend-egress.service <<'EOF'
[Unit]
Description=Block Backend containers from the global internet
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/wildlife-backend-egress
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now wildlife-backend-egress.service
}


sync_clock
disable_old_runtime
enable_persistent_journal

if [ "$ROLE" = "logging" ]; then
    install_logging_dependencies
else
    install_docker_compose
fi

install_ssh_user

if [ "$ROLE" = "logging" ]; then
    remove_legacy_logging_stack
    install_log_collector
    systemctl status wildlife-log-collector.timer --no-pager
    exit 0
fi

install_log_collector_access

if [ "$ROLE" = "backend" ]; then
    install_backend_egress_filter
fi

compose up --detach --build --remove-orphans
docker volume rm wildlife_alloy_data >/dev/null 2>&1 || true
docker image rm grafana/alloy:v1.18.0 >/dev/null 2>&1 || true

case "$ROLE" in
    fetcher)
        install_fetcher_timer
        wait_http "http://${FETCHER_HOST}:8002/health" "Fetcher"
        ;;
    backend)
        wait_http "http://${BACKEND_HOST}:8000/health" "Backend"
        ;;
    ui)
        compose exec -T caddy \
            caddy reload \
            --config /etc/caddy/Caddyfile \
            --adapter caddyfile
        export_ui_ca_certificate
        wait_https \
            "https://${UI_HOST}/health" \
            "${PROJECT_ROOT}/tls/wildlife-local-root-ca.crt" \
            "UI HTTPS"
        ;;
esac

compose ps
