#!/usr/bin/env bash
set -euo pipefail

source /vagrant/provision/common.sh

log() {
    printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

log "Removing old host-level Backend services"
systemctl disable --now backend-api backend-consumer 2>/dev/null || true
rm -f /etc/systemd/system/backend-api.service /etc/systemd/system/backend-consumer.service

rm -rf /opt/weatherflow/backend
mkdir -p /opt/weatherflow/backend
rsync -a --delete /vagrant/backend/ /opt/weatherflow/backend/
install -m 0644 /vagrant/compose/backend/compose.yml /opt/weatherflow/compose.yml

cat > /usr/local/bin/weatherflow-compose-up <<'UP'
#!/usr/bin/env bash
set -euo pipefail
source /usr/local/lib/weatherflow/network.sh

DB_IP="$(resolve_lan_host db.local)"
cat > /opt/weatherflow/runtime.env <<EOF
DB_HOST=${DB_IP}
DB_PORT=5432
DB_NAME=weather_db
DB_USER=weather_user
DB_PASSWORD=weather_password
RABBITMQ_HOST=${DB_IP}
RABBITMQ_PORT=5672
RABBITMQ_USER=weather
RABBITMQ_PASSWORD=weather_rabbit_password
RABBITMQ_VHOST=weather
RABBITMQ_QUEUE=weather_updates
EOF
chmod 0600 /opt/weatherflow/runtime.env

cd /opt/weatherflow
docker compose --env-file runtime.env -f compose.yml up -d --build --remove-orphans
UP
chmod 0755 /usr/local/bin/weatherflow-compose-up

cat > /etc/systemd/system/weatherflow-compose.service <<'UNIT'
[Unit]
Description=WeatherFlow Docker Compose stack on Backend VM
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

log "Waiting for Backend API container"
for _ in $(seq 1 90); do
    if docker inspect --format '{{.State.Health.Status}}' weatherflow-backend-api 2>/dev/null | grep -qx healthy; then
        break
    fi
    sleep 2
done

if ! docker inspect --format '{{.State.Health.Status}}' weatherflow-backend-api 2>/dev/null | grep -qx healthy; then
    docker logs --tail 100 weatherflow-backend-api || true
    docker logs --tail 100 weatherflow-backend-consumer || true
    echo "Backend API container is not healthy" >&2
    exit 1
fi

if ! docker inspect --format '{{.State.Running}}' weatherflow-backend-consumer 2>/dev/null | grep -qx true; then
    docker logs --tail 100 weatherflow-backend-consumer || true
    echo "Backend Consumer container is not running" >&2
    exit 1
fi

docker compose --env-file /opt/weatherflow/runtime.env -f /opt/weatherflow/compose.yml ps
source /etc/weatherflow/lan.env
printf '\nBackend is available directly in the physical LAN:\n'
printf '  API: http://%s:5000/health\n' "$LAN_IP"
