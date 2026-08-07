#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${PROJECT_ROOT}/deploy.env"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Create deploy.env from deploy.env.example first." >&2
    exit 1
fi

set -a
# shellcheck disable=SC1090
source "$CONFIG_FILE"
set +a

SSH_USER="${SSH_USER:-ubuntu}"
SSH_ARGS=(-o StrictHostKeyChecking=accept-new)
if [ -n "${SSH_KEY_PATH:-}" ]; then
    SSH_ARGS+=(-i "$SSH_KEY_PATH")
fi

deploy_role() {
    local role="$1"
    local host="$2"
    local remote_root="/tmp/wildlife-deploy"
    local destination="${SSH_USER}@${host}"

    echo "Deploying ${role} to ${destination}"
    ssh "${SSH_ARGS[@]}" "$destination" "mkdir -p ${remote_root}"
    tar \
        --exclude=".git" \
        --exclude=".vagrant" \
        --exclude=".venv" \
        --exclude="__pycache__" \
        --exclude="*.pyc" \
        --exclude="tls/*.crt" \
        -czf - \
        -C "$PROJECT_ROOT" . \
    | ssh "${SSH_ARGS[@]}" "$destination" \
        "tar -xzf - -C ${remote_root}"
    ssh -t "${SSH_ARGS[@]}" "$destination" \
        "sudo PROJECT_ROOT=${remote_root} ${remote_root}/provision/node.sh ${role}"
}

deploy_role "logging" "$LOGGING_HOST"

scp "${SSH_ARGS[@]}" \
    "${SSH_USER}@${LOGGING_HOST}:/tmp/wildlife-deploy/logging/wildlife-log-collector.pub" \
    "${PROJECT_ROOT}/logging/wildlife-log-collector.pub"

deploy_role "database" "$DB_HOST"
deploy_role "redis" "$REDIS_HOST"
deploy_role "fetcher" "$FETCHER_HOST"
deploy_role "backend" "$BACKEND_HOST"
deploy_role "ui" "$UI_HOST"

echo "Deployment completed. Open https://${UI_HOST}"
echo "Centralized logs: ${SSH_USER}@${LOGGING_HOST}:/var/log/wildlife"
echo "Copy the public CA certificate from:"
echo "  ${SSH_USER}@${UI_HOST}:/tmp/wildlife-deploy/tls/wildlife-local-root-ca.crt"
echo "Then trust the copied certificate on the Linux client with:"
echo "  bash ./install-local-ca.sh /path/to/wildlife-local-root-ca.crt"
