#!/usr/bin/env bash
set -Eeuo pipefail

log() {
    printf '\n[%s] %s\n' "$(date --iso-8601=seconds)" "$*"
}

required_variables=(
    AIRAWARE_ROLE
    AIRAWARE_BACKEND_IP
    AIRAWARE_DATABASE_IP
    AIRAWARE_DB_NAME
    AIRAWARE_DB_USER
    AIRAWARE_DB_PASSWORD
    AIRAWARE_REDIS_PASSWORD
    AIRAWARE_FLASK_SECRET_KEY
    AIRAWARE_RABBITMQ_USER
    AIRAWARE_RABBITMQ_PASSWORD
    AIRAWARE_RABBITMQ_VHOST
)

for variable_name in "${required_variables[@]}"; do
    if [[ -z "${!variable_name:-}" ]]; then
        echo "Required variable is missing: ${variable_name}" >&2
        exit 1
    fi
done

SOURCE_ROOT=/vagrant
DEPLOY_ROOT=/opt/airaware

sync_service() {
    local service_directory="$1"

    install -d -m 0755 "${DEPLOY_ROOT}/${service_directory}"
    rsync -a \
        --exclude='.env' \
        --exclude='.venv/' \
        --exclude='__pycache__/' \
        --exclude='.mypy_cache/' \
        --exclude='.pytest_cache/' \
        --exclude='.ruff_cache/' \
        --exclude='*.py[cod]' \
        "${SOURCE_ROOT}/${service_directory}/" \
        "${DEPLOY_ROOT}/${service_directory}/"
}

if [[ ! -f "${SOURCE_ROOT}/deploy/${AIRAWARE_ROLE}/compose.yml" ]]; then
    # Vagrant machine name remains database while deployment role is infrastructure.
    if [[ "${AIRAWARE_ROLE}" == "database" ]]; then
        COMPOSE_ROLE=infrastructure
    else
        COMPOSE_ROLE="${AIRAWARE_ROLE}"
    fi
else
    COMPOSE_ROLE="${AIRAWARE_ROLE}"
fi

log "Preparing Docker Compose deployment for ${AIRAWARE_ROLE}"

# Stop the previous native deployment so it cannot occupy container ports.
case "${AIRAWARE_ROLE}" in
    frontend)
        systemctl disable --now airaware-frontend.service 2>/dev/null || true
        ;;
    backend)
        systemctl disable --now airaware-backend.service 2>/dev/null || true
        systemctl disable --now airaware-backend-consumer.service 2>/dev/null || true
        ;;
    fetcher)
        systemctl disable --now airaware-fetcher.service 2>/dev/null || true
        ;;
    database)
        systemctl disable --now postgresql.service 2>/dev/null || true
        systemctl disable --now redis-server.service 2>/dev/null || true
        systemctl disable --now rabbitmq-server.service 2>/dev/null || true
        ;;
esac

rm -rf "${DEPLOY_ROOT:?}/"*
install -d -m 0755 "${DEPLOY_ROOT}"

case "${AIRAWARE_ROLE}" in
    frontend)
        sync_service frontend-service
        ;;
    backend)
        sync_service backend-service
        ;;
    fetcher)
        sync_service api-fetcher-service
        ;;
    database)
        install -d -m 0755 "${DEPLOY_ROOT}/backend-service/database"
        install -m 0644 \
            "${SOURCE_ROOT}/backend-service/database/init.sql" \
            "${DEPLOY_ROOT}/backend-service/database/init.sql"
        ;;
    *)
        echo "Unsupported role: ${AIRAWARE_ROLE}" >&2
        exit 1
        ;;
esac

install -d -m 0755 "${DEPLOY_ROOT}/deploy"
install -d -m 0755 "${DEPLOY_ROOT}/deploy/${COMPOSE_ROLE}"
rsync -a \
    --exclude='.env' \
    "${SOURCE_ROOT}/deploy/${COMPOSE_ROLE}/" \
    "${DEPLOY_ROOT}/deploy/${COMPOSE_ROLE}/"

python3 - "$AIRAWARE_DB_PASSWORD" \
    "$AIRAWARE_RABBITMQ_USER" "$AIRAWARE_RABBITMQ_PASSWORD" \
    "$AIRAWARE_RABBITMQ_VHOST" <<'PY' \
    > /tmp/airaware-encoded-env
import sys
from urllib.parse import quote
for value in sys.argv[1:]:
    print(quote(value, safe=""))
PY

mapfile -t encoded_values </tmp/airaware-encoded-env
rm -f /tmp/airaware-encoded-env
encoded_database_password="${encoded_values[0]}"
encoded_rabbitmq_user="${encoded_values[1]}"
encoded_rabbitmq_password="${encoded_values[2]}"
encoded_rabbitmq_vhost="${encoded_values[3]}"

ENV_FILE="${DEPLOY_ROOT}/deploy/${COMPOSE_ROLE}/.env"

case "${AIRAWARE_ROLE}" in
    frontend)
        cat >"${ENV_FILE}" <<ENV
BACKEND_SERVICE_URL=http://${AIRAWARE_BACKEND_IP}:8001
HTTP_TIMEOUT_SECONDS=10
SESSION_TTL_SECONDS=86400
FLASK_SECRET_KEY=${AIRAWARE_FLASK_SECRET_KEY}
ENV
        ;;
    backend)
        cat >"${ENV_FILE}" <<ENV
DATABASE_URL=postgresql+psycopg://${AIRAWARE_DB_USER}:${encoded_database_password}@${AIRAWARE_DATABASE_IP}:5432/${AIRAWARE_DB_NAME}
DATABASE_CONNECT_TIMEOUT_SECONDS=5
RABBITMQ_URL=amqp://${encoded_rabbitmq_user}:${encoded_rabbitmq_password}@${AIRAWARE_DATABASE_IP}:5672/${encoded_rabbitmq_vhost}
RABBITMQ_CONNECTION_TIMEOUT_SECONDS=10
RABBITMQ_EXCHANGE=airaware.measurements
RABBITMQ_QUEUE=airaware.measurements.persist
RABBITMQ_ROUTING_KEY=measurement.created
RABBITMQ_DEAD_LETTER_EXCHANGE=airaware.measurements.dead-letter
RABBITMQ_DEAD_LETTER_QUEUE=airaware.measurements.dead-letter
RABBITMQ_CONSUMER_ENABLED=true
RABBITMQ_RETRY_DELAY_SECONDS=5
ENV
        ;;
    fetcher)
        cat >"${ENV_FILE}" <<ENV
OPEN_METEO_AIR_QUALITY_URL=https://air-quality-api.open-meteo.com/v1/air-quality
BACKEND_SERVICE_URL=http://${AIRAWARE_BACKEND_IP}:8001
RABBITMQ_URL=amqp://${encoded_rabbitmq_user}:${encoded_rabbitmq_password}@${AIRAWARE_DATABASE_IP}:5672/${encoded_rabbitmq_vhost}
RABBITMQ_EXCHANGE=airaware.measurements
RABBITMQ_QUEUE=airaware.measurements.persist
RABBITMQ_ROUTING_KEY=measurement.created
RABBITMQ_DEAD_LETTER_EXCHANGE=airaware.measurements.dead-letter
RABBITMQ_DEAD_LETTER_QUEUE=airaware.measurements.dead-letter
RABBITMQ_CONNECTION_TIMEOUT_SECONDS=10
RABBITMQ_BLOCKED_CONNECTION_TIMEOUT_SECONDS=15
RABBITMQ_CONNECTION_ATTEMPTS=3
RABBITMQ_RETRY_DELAY_SECONDS=2
HTTP_TIMEOUT_SECONDS=15
FETCH_ON_STARTUP=true
SCHEDULER_ENABLED=true
FETCH_MINUTE_OF_HOUR=5
ENV
        ;;
    database)
        cat >"${ENV_FILE}" <<ENV
POSTGRES_DB=${AIRAWARE_DB_NAME}
POSTGRES_USER=${AIRAWARE_DB_USER}
POSTGRES_PASSWORD=${AIRAWARE_DB_PASSWORD}
REDIS_PASSWORD=${AIRAWARE_REDIS_PASSWORD}
RABBITMQ_USER=${AIRAWARE_RABBITMQ_USER}
RABBITMQ_PASSWORD=${AIRAWARE_RABBITMQ_PASSWORD}
RABBITMQ_VHOST=${AIRAWARE_RABBITMQ_VHOST}
ENV
        ;;
esac

chmod 0600 "${ENV_FILE}"

cd "${DEPLOY_ROOT}/deploy/${COMPOSE_ROLE}"
log "Pulling/building container images"
docker compose pull --ignore-buildable
docker compose build --pull
log "Starting containers"
if ! docker compose up \
    -d \
    --remove-orphans \
    --wait \
    --wait-timeout 180; then
    log "Containers did not become healthy before the deployment timeout"
    docker compose ps --all || true
    docker compose logs --no-color --tail 200 || true
    exit 1
fi

docker compose ps
log "Docker Compose deployment completed"
