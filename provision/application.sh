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

case "${AIRAWARE_ROLE}" in
    backend)
        SOURCE_DIRECTORY="/vagrant/backend-service"
        SERVICE_DIRECTORY="/opt/airaware/backend-service"
        SERVICE_NAME="airaware-backend"
        SERVICE_PORT="8001"
        SERVICE_DESCRIPTION="AirAware Backend Service"
        START_COMMAND="${SERVICE_DIRECTORY}/.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port ${SERVICE_PORT}"
        ;;

    fetcher)
        SOURCE_DIRECTORY="/vagrant/api-fetcher-service"
        SERVICE_DIRECTORY="/opt/airaware/api-fetcher-service"
        SERVICE_NAME="airaware-fetcher"
        SERVICE_PORT="8000"
        SERVICE_DESCRIPTION="AirAware API Fetcher Service"
        START_COMMAND="${SERVICE_DIRECTORY}/.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port ${SERVICE_PORT}"
        ;;

    frontend)
        SOURCE_DIRECTORY="/vagrant/frontend-service"
        SERVICE_DIRECTORY="/opt/airaware/frontend-service"
        SERVICE_NAME="airaware-frontend"
        SERVICE_PORT="5000"
        SERVICE_DESCRIPTION="AirAware Frontend Service"
        START_COMMAND="${SERVICE_DIRECTORY}/.venv/bin/python -m flask --app app.main run --host 0.0.0.0 --port ${SERVICE_PORT}"
        ;;

    *)
        echo "Unsupported application role: ${AIRAWARE_ROLE}" >&2
        exit 1
        ;;
esac

if [[ ! -d "${SOURCE_DIRECTORY}" ]]; then
    echo "Application source is missing: ${SOURCE_DIRECTORY}" >&2
    exit 1
fi

if [[ ! -f "${SOURCE_DIRECTORY}/requirements.txt" ]]; then
    echo "requirements.txt is missing in ${SOURCE_DIRECTORY}" >&2
    exit 1
fi

log "Installing Python runtime for ${AIRAWARE_ROLE}"

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    rsync \
    curl

log "Deploying ${AIRAWARE_ROLE} source code"

install -d \
    -o airaware \
    -g airaware \
    -m 0755 \
    "${SERVICE_DIRECTORY}"

rsync \
    --archive \
    --delete \
    --exclude='.env' \
    --exclude='.venv' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    "${SOURCE_DIRECTORY}/" \
    "${SERVICE_DIRECTORY}/"

chown -R airaware:airaware "${SERVICE_DIRECTORY}"

if [[ ! -x "${SERVICE_DIRECTORY}/.venv/bin/python" ]]; then
    python3 -m venv "${SERVICE_DIRECTORY}/.venv"
fi

"${SERVICE_DIRECTORY}/.venv/bin/python" \
    -m pip install \
    --upgrade pip

"${SERVICE_DIRECTORY}/.venv/bin/python" \
    -m pip install \
    --requirement "${SERVICE_DIRECTORY}/requirements.txt"

encoded_database_password="$(
    python3 -c \
        'import sys; from urllib.parse import quote; print(quote(sys.argv[1], safe=""))' \
        "${AIRAWARE_DB_PASSWORD}"
)"

encoded_rabbitmq_user="$(
    python3 -c \
        'import sys; from urllib.parse import quote; print(quote(sys.argv[1], safe=""))' \
        "${AIRAWARE_RABBITMQ_USER}"
)"

encoded_rabbitmq_password="$(
    python3 -c \
        'import sys; from urllib.parse import quote; print(quote(sys.argv[1], safe=""))' \
        "${AIRAWARE_RABBITMQ_PASSWORD}"
)"

encoded_rabbitmq_vhost="$(
    python3 -c \
        'import sys; from urllib.parse import quote; print(quote(sys.argv[1], safe=""))' \
        "${AIRAWARE_RABBITMQ_VHOST}"
)"

log "Creating service environment configuration"

case "${AIRAWARE_ROLE}" in
    backend)
        cat >"${SERVICE_DIRECTORY}/.env" <<EOF
DATABASE_URL=postgresql+psycopg://${AIRAWARE_DB_USER}:${encoded_database_password}@${AIRAWARE_DATABASE_IP}:5432/${AIRAWARE_DB_NAME}
RABBITMQ_URL=amqp://${encoded_rabbitmq_user}:${encoded_rabbitmq_password}@${AIRAWARE_DATABASE_IP}:5672/${encoded_rabbitmq_vhost}
RABBITMQ_EXCHANGE=airaware.measurements
RABBITMQ_QUEUE=airaware.measurements.persist
RABBITMQ_ROUTING_KEY=measurement.created
RABBITMQ_DEAD_LETTER_EXCHANGE=airaware.measurements.dead-letter
RABBITMQ_DEAD_LETTER_QUEUE=airaware.measurements.dead-letter
EOF
        ;;

    fetcher)
        cat >"${SERVICE_DIRECTORY}/.env" <<EOF
OPEN_METEO_AIR_QUALITY_URL=https://air-quality-api.open-meteo.com/v1/air-quality
BACKEND_SERVICE_URL=http://${AIRAWARE_BACKEND_IP}:8001
RABBITMQ_URL=amqp://${encoded_rabbitmq_user}:${encoded_rabbitmq_password}@${AIRAWARE_DATABASE_IP}:5672/${encoded_rabbitmq_vhost}
RABBITMQ_EXCHANGE=airaware.measurements
RABBITMQ_QUEUE=airaware.measurements.persist
RABBITMQ_ROUTING_KEY=measurement.created
RABBITMQ_DEAD_LETTER_EXCHANGE=airaware.measurements.dead-letter
RABBITMQ_DEAD_LETTER_QUEUE=airaware.measurements.dead-letter
HTTP_TIMEOUT_SECONDS=15
FETCH_ON_STARTUP=true
SCHEDULER_ENABLED=true
FETCH_MINUTE_OF_HOUR=5
EOF
        ;;

frontend)
    cat >"${SERVICE_DIRECTORY}/.env" <<EOF
BACKEND_SERVICE_URL=http://${AIRAWARE_BACKEND_IP}:8001
HTTP_TIMEOUT_SECONDS=10

REDIS_URL=redis://:${AIRAWARE_REDIS_PASSWORD}@${AIRAWARE_DATABASE_IP}:6379/0
SESSION_KEY_PREFIX=airaware:session:
SESSION_TTL_SECONDS=86400
FLASK_SECRET_KEY=${AIRAWARE_FLASK_SECRET_KEY}
EOF
    ;;
esac

chown airaware:airaware "${SERVICE_DIRECTORY}/.env"
chmod 0600 "${SERVICE_DIRECTORY}/.env"

log "Creating systemd service ${SERVICE_NAME}"

cat >"/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=${SERVICE_DESCRIPTION}
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=airaware
Group=airaware
WorkingDirectory=${SERVICE_DIRECTORY}
Environment=PYTHONUNBUFFERED=1
ExecStart=${START_COMMAND}
Restart=always
RestartSec=5
TimeoutStopSec=20

[Install]
WantedBy=multi-user.target
EOF


if [[ "${AIRAWARE_ROLE}" == "backend" ]]; then
    cat >"/etc/systemd/system/airaware-backend-consumer.service" <<EOF
[Unit]
Description=AirAware Backend RabbitMQ Consumer
Wants=network-online.target
After=network-online.target airaware-backend.service

[Service]
Type=simple
User=airaware
Group=airaware
WorkingDirectory=${SERVICE_DIRECTORY}
Environment=PYTHONUNBUFFERED=1
ExecStart=${SERVICE_DIRECTORY}/.venv/bin/python -m app.consumer
Restart=always
RestartSec=5
TimeoutStopSec=20

[Install]
WantedBy=multi-user.target
EOF
fi

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"
systemctl restart "${SERVICE_NAME}"

if [[ "${AIRAWARE_ROLE}" == "backend" ]]; then
    systemctl enable airaware-backend-consumer
    systemctl restart airaware-backend-consumer
fi

log "Waiting for ${SERVICE_NAME} HTTP endpoint"

service_ready=false

for attempt in $(seq 1 30); do
    if curl \
        --fail \
        --silent \
        --show-error \
        "http://127.0.0.1:${SERVICE_PORT}/health" \
        >/dev/null; then

        service_ready=true
        break
    fi

    sleep 2
done

if [[ "${service_ready}" != "true" ]]; then
    log "${SERVICE_NAME} did not become healthy"
    systemctl status "${SERVICE_NAME}" --no-pager || true
    journalctl \
        --unit="${SERVICE_NAME}" \
        --no-pager \
        --lines=100 || true
    exit 1
fi

log "${SERVICE_NAME} is healthy"
systemctl status "${SERVICE_NAME}" --no-pager

log "${AIRAWARE_ROLE} provisioning completed"
