#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -f "${PROJECT_ROOT}/deploy.env" ]; then
    echo "Create deploy.env first:" >&2
    echo "  cp deploy.env.example deploy.env" >&2
    exit 1
fi

cd "$PROJECT_ROOT"

for role in logging database redis fetcher backend ui; do
    echo "Starting and provisioning the ${role} VM..."
    vagrant up "$role" --provider=virtualbox --provision
done

"${PROJECT_ROOT}/setup-ssh-config.sh"

set -a
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/deploy.env"
set +a

echo
echo "All VMs were provisioned."
echo "Site: https://${UI_HOST}"
echo "Logs: ssh logging, then sudo ls -lh /var/log/wildlife"
echo "Local CA: ${PROJECT_ROOT}/tls/wildlife-local-root-ca.crt"
echo "Trust it on Linux with: bash ./install-local-ca.sh"
echo "Backend: http://${BACKEND_HOST}:8000/health"
echo "Fetcher: http://${FETCHER_HOST}:8002/health"
