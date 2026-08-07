#!/usr/bin/env bash
set -euo pipefail

source /vagrant/provision/common.sh

log() {
    printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

log "Removing old host-level Fetcher service"
systemctl disable --now fetcher 2>/dev/null || true
rm -f /etc/systemd/system/fetcher.service

rm -rf /opt/weatherflow/fetcher
mkdir -p /opt/weatherflow/fetcher
rsync -a --delete /vagrant/fetcher/ /opt/weatherflow/fetcher/
install -m 0644 /vagrant/compose/fetcher/compose.yml /opt/weatherflow/compose.yml

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
WEATHER_API_URL=https://api.open-meteo.com/v1/forecast
FETCH_INTERVAL_SECONDS=1800
EOF
chmod 0600 /opt/weatherflow/runtime.env

cd /opt/weatherflow
docker compose --env-file runtime.env -f compose.yml up -d --build --remove-orphans
UP
chmod 0755 /usr/local/bin/weatherflow-compose-up

cat > /etc/systemd/system/weatherflow-compose.service <<'UNIT'
[Unit]
Description=WeatherFlow Docker Compose stack on Fetcher VM
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

sleep 3
if ! docker inspect --format '{{.State.Running}}' weatherflow-fetcher 2>/dev/null | grep -qx true; then
    docker logs --tail 100 weatherflow-fetcher || true
    echo "Fetcher container is not running" >&2
    exit 1
fi

docker compose --env-file /opt/weatherflow/runtime.env -f /opt/weatherflow/compose.yml ps
source /etc/weatherflow/lan.env
printf '\nFetcher container runs on LAN VM %s and publishes to db.local/RabbitMQ.\n' "$LAN_IP"
