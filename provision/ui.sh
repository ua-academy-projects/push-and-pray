#!/usr/bin/env bash
set -euo pipefail

source /vagrant/provision/common.sh

log() {
    printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

log "Removing old host-level UI service"
systemctl disable --now ui 2>/dev/null || true
rm -f /etc/systemd/system/ui.service

rm -rf /opt/weatherflow/ui
mkdir -p /opt/weatherflow/ui
rsync -a --delete /vagrant/ui/ /opt/weatherflow/ui/
install -m 0644 /vagrant/compose/ui/compose.yml /opt/weatherflow/compose.yml

cat > /usr/local/bin/weatherflow-compose-up <<'UP'
#!/usr/bin/env bash
set -euo pipefail
source /usr/local/lib/weatherflow/network.sh

DB_IP="$(resolve_lan_host db.local)"
BACKEND_IP="$(resolve_lan_host backend.local)"
cat > /opt/weatherflow/runtime.env <<EOF
BACKEND_URL=http://${BACKEND_IP}:5000
REDIS_HOST=${DB_IP}
REDIS_PORT=6379
REDIS_PASSWORD=weather_redis_password
SESSION_SECRET=weather-session-secret-for-training-project
REQUEST_TIMEOUT=20
EOF
chmod 0600 /opt/weatherflow/runtime.env

cd /opt/weatherflow
docker compose --env-file runtime.env -f compose.yml up -d --build --remove-orphans
UP
chmod 0755 /usr/local/bin/weatherflow-compose-up

cat > /etc/systemd/system/weatherflow-compose.service <<'UNIT'
[Unit]
Description=WeatherFlow Docker Compose stack on UI VM
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

log "Waiting for UI container"
for _ in $(seq 1 90); do
    if docker inspect --format '{{.State.Health.Status}}' weatherflow-ui 2>/dev/null | grep -qx healthy; then
        break
    fi
    sleep 2
done

if ! docker inspect --format '{{.State.Health.Status}}' weatherflow-ui 2>/dev/null | grep -qx healthy; then
    docker logs --tail 100 weatherflow-ui || true
    echo "UI container is not healthy" >&2
    exit 1
fi

docker compose --env-file /opt/weatherflow/runtime.env -f /opt/weatherflow/compose.yml ps
source /etc/weatherflow/lan.env
printf '\nUI is available directly in the physical LAN:\n'
printf '  http://%s:5000\n' "$LAN_IP"
printf '  Optional mDNS name: http://ui.local:5000\n'
