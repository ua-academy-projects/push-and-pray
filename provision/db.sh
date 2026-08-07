#!/usr/bin/env bash
set -euo pipefail

source /vagrant/provision/common.sh

log() {
    printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

log "Removing old host-level database services so Docker owns their ports"
for service in postgresql redis-server rabbitmq-server; do
    systemctl disable --now "$service" 2>/dev/null || true
done

rm -rf /opt/weatherflow/db
mkdir -p /opt/weatherflow/db
rsync -a --delete /vagrant/db/ /opt/weatherflow/db/
install -m 0644 /vagrant/compose/db/compose.yml /opt/weatherflow/compose.yml

cat > /opt/weatherflow/runtime.env <<'ENV'
POSTGRES_DB=weather_db
POSTGRES_USER=weather_user
POSTGRES_PASSWORD=weather_password
REDIS_PASSWORD=weather_redis_password
RABBITMQ_DEFAULT_USER=weather
RABBITMQ_DEFAULT_PASS=weather_rabbit_password
RABBITMQ_DEFAULT_VHOST=weather
ENV
chmod 0600 /opt/weatherflow/runtime.env

cat > /usr/local/bin/weatherflow-compose-up <<'UP'
#!/usr/bin/env bash
set -euo pipefail
cd /opt/weatherflow

docker compose --env-file runtime.env -f compose.yml up -d \
    postgres redis rabbitmq

for _ in $(seq 1 90); do
    if docker compose --env-file runtime.env -f compose.yml exec -T postgres \
        pg_isready -U weather_user -d weather_db >/dev/null 2>&1; then
        break
    fi
    sleep 2
done

docker compose --env-file runtime.env -f compose.yml run --rm db-init
UP
chmod 0755 /usr/local/bin/weatherflow-compose-up

cat > /etc/systemd/system/weatherflow-compose.service <<'UNIT'
[Unit]
Description=WeatherFlow Docker Compose stack on DB VM
Requires=docker.service
After=docker.service network-online.target avahi-daemon.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/weatherflow-compose-up
ExecStop=/usr/bin/docker compose --env-file /opt/weatherflow/runtime.env -f /opt/weatherflow/compose.yml stop
RemainAfterExit=yes
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable weatherflow-compose.service
systemctl restart weatherflow-compose.service

log "Waiting for all DB/infra containers"
for _ in $(seq 1 90); do
    if docker inspect --format '{{.State.Health.Status}}' weatherflow-postgres 2>/dev/null | grep -qx healthy \
       && docker inspect --format '{{.State.Health.Status}}' weatherflow-redis 2>/dev/null | grep -qx healthy \
       && docker inspect --format '{{.State.Health.Status}}' weatherflow-rabbitmq 2>/dev/null | grep -qx healthy; then
        break
    fi
    sleep 2
done

for container in weatherflow-postgres weatherflow-redis weatherflow-rabbitmq; do
    if ! docker inspect --format '{{.State.Health.Status}}' "$container" 2>/dev/null | grep -qx healthy; then
        docker logs --tail 100 "$container" || true
        echo "Container is not healthy: $container" >&2
        exit 1
    fi
done

docker compose --env-file /opt/weatherflow/runtime.env -f /opt/weatherflow/compose.yml ps
source /etc/weatherflow/lan.env
printf '\nDB/Infra is available directly in the physical LAN:\n'
printf '  PostgreSQL: %s:5432\n' "$LAN_IP"
printf '  Redis:      %s:6379\n' "$LAN_IP"
printf '  RabbitMQ:   %s:5672\n' "$LAN_IP"
printf '  Management: http://%s:15672\n' "$LAN_IP"
