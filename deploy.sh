#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$PWD"
CONFIG="$ROOT/project-config.json"

[ -f ~/.oilscope_cf_token ] && export TF_VAR_cloudflare_api_token="$(cat ~/.oilscope_cf_token)"

cd infrastructure/terraform
terraform init -input=false >/dev/null

if [ "${1:-}" = "destroy" ]; then
  terraform destroy -auto-approve -var "project_config_path=$CONFIG"
  exit 0
fi

terraform apply -auto-approve -var "project_config_path=$CONFIG"

managed_db_host="$(terraform output -raw managed_db_private_ip 2>/dev/null || true)"
tunnel_token="$(terraform output -raw cloudflare_tunnel_token 2>/dev/null || true)"

cd ../ansible
export OILSCOPE_PROJECT_CONFIG="$CONFIG"
export OILSCOPE_SSH_USER="${OILSCOPE_SSH_USER:-artur}"
: "${OILSCOPE_SSH_KEY:?set OILSCOPE_SSH_KEY to your private key path}"

auth="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/containers/auth.json"
export EXAMPLE_API_KEY="$(grep -E '^OILPRICEAPI_KEY=' "$ROOT/.env" | cut -d= -f2-)"
export EXAMPLE_GHCR_TOKEN="$(python3 -c "import json,base64;print(base64.b64decode(json.load(open('$auth'))['auths']['ghcr.io']['auth']).decode().split(':',1)[1])")"

ansible-galaxy collection build oilscope/platform --output-path /tmp --force >/dev/null
ansible-galaxy collection install /tmp/oilscope-platform-*.tar.gz --force >/dev/null

ansible-playbook oilscope.platform.bootstrap_bastion -i inventory/oilscope.yml -e project_config_path="$CONFIG"
ansible-playbook oilscope.platform.upload_secret_versions -i inventory/oilscope.yml -e secret_versions_config_file="$CONFIG"
ansible-playbook oilscope.platform.deploy_workloads -i inventory/oilscope.yml \
  -e project_config_path="$CONFIG" \
  -e managed_db_host_value="$managed_db_host" \
  -e cloudflared_tunnel_token_value="$tunnel_token"
