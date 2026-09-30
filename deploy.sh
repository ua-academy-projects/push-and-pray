#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$PWD"
CONFIG="$ROOT/dev.json"

cf_token=""
[ -f ~/.oilscope_cf_token ] && cf_token="$(cat ~/.oilscope_cf_token)"
[ -n "$cf_token" ] && export TF_VAR_cloudflare_api_token="$cf_token"

cd infrastructure/terraform
terraform init -input=false >/dev/null

if [ "${1:-}" = "destroy" ]; then
  terraform destroy -auto-approve -var "project_config_path=$CONFIG"
  exit 0
fi

terraform apply -auto-approve -var "project_config_path=$CONFIG"

tunnel_token="$(terraform output -raw cloudflare_tunnel_token 2>/dev/null || true)"

cd ../ansible
export OILSCOPE_PROJECT_CONFIG="$CONFIG"
export OILSCOPE_SSH_USER="${OILSCOPE_SSH_USER:-artur}"
: "${OILSCOPE_SSH_KEY:?set OILSCOPE_SSH_KEY to your private key path}"

auth="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/containers/auth.json"
export OILPRICEAPI_KEY="$(grep -E '^OILPRICEAPI_KEY=' "$ROOT/.env" | cut -d= -f2-)"
export GHCR_TOKEN="$(python3 -c "import json,base64;print(base64.b64decode(json.load(open('$auth'))['auths']['ghcr.io']['auth']).decode().split(':',1)[1])")"

ts_authkey=""
[ -f ~/.oilscope_tailscale_authkey ] && ts_authkey="$(cat ~/.oilscope_tailscale_authkey)"

ansible-galaxy collection install ./oilscope/platform --force >/dev/null

ansible-playbook oilscope.platform.bootstrap_bastion -i inventory/oilscope.yml \
  -e project_config_path="$CONFIG" \
  -e tailscale_authkey="$ts_authkey"
ansible-playbook oilscope.platform.upload_secret_versions -i inventory/oilscope.yml -e secret_versions_config_file="$CONFIG"
ansible-playbook oilscope.platform.k3s -i inventory/oilscope.yml \
  -e project_config_path="$CONFIG" \
  -e cloudflare_api_token="$cf_token" \
  -e cloudflared_tunnel_token="$tunnel_token"
