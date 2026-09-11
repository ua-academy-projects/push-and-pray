#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
readonly REPO_ROOT
readonly TF_DIR="${REPO_ROOT}/infrastructure/terraform"
readonly ANSIBLE_DIR="${REPO_ROOT}/infrastructure/ansible"
readonly INVENTORY="${ANSIBLE_DIR}/inventory/oilscope.yml"
readonly COLLECTION_DIR="${ANSIBLE_DIR}/oilscope/platform"
readonly DOMAIN="shiphappens.pp.ua"
readonly DEPLOY_VENV="${REPO_ROOT}/.oilscope-deploy/venv"
readonly DEPLOY_ENV_FILE="${OILSCOPE_DEPLOY_ENV_FILE:-${REPO_ROOT}/.env}"

if [[ -f "${DEPLOY_ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${DEPLOY_ENV_FILE}"
  set +a
fi

PROFILE="${1:-${OILSCOPE_DEPLOY_PROFILE:-}}"
case "${PROFILE}" in
  aws|gcp|mixed)
    CONFIG_INPUT="${REPO_ROOT}/configs/project-config.${PROFILE}.json"
    ;;
  "")
    CONFIG_INPUT="${OILSCOPE_PROJECT_CONFIG:-${REPO_ROOT}/project-config.json}"
    PROFILE="custom"
    ;;
  *.json|*/*.json)
    CONFIG_INPUT="${PROFILE}"
    PROFILE="custom"
    ;;
  *)
    printf "ERROR: Unknown deployment profile '%s'. Use aws, gcp, mixed, or a JSON config path.\n" "${PROFILE}" >&2
    exit 1
    ;;
esac

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

step() {
  printf '\n==> %s\n' "$*"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

if [[ ! -f "${CONFIG_INPUT}" ]]; then
  fail "Project config not found: ${CONFIG_INPUT}. Pass its path as the first argument."
fi

CONFIG_DIR="$(cd "$(dirname "${CONFIG_INPUT}")" && pwd -P)"
readonly CONFIG_DIR
CONFIG="${CONFIG_DIR}/$(basename "${CONFIG_INPUT}")"
readonly CONFIG
readonly PROFILE
readonly TF_STATE_DIR="${TF_DIR}/.state"
readonly TF_STATE_PATH="${TF_STATE_DIR}/${PROFILE}.tfstate"
case "${PROFILE}" in
  aws|gcp)
    TF_RUN_DIR="${TF_DIR}/stacks/${PROFILE}"
    ;;
  *)
    TF_RUN_DIR="${TF_DIR}"
    ;;
esac
readonly TF_RUN_DIR

for command_name in jq terraform curl dig nc python3; do
  require_command "${command_name}"
done

step "Validating project configuration"
jq empty "${CONFIG}"

if command -v uvx >/dev/null 2>&1; then
  uvx check-jsonschema \
    --schemafile "${TF_DIR}/project-config.schema.json" \
    "${CONFIG}"
else
  printf 'WARNING: uvx is unavailable; JSON syntax was checked, but JSON Schema validation was skipped.\n' >&2
fi

CONFIG_DOMAIN="$(jq -r '.vms.ui.public_endpoint.hostname // empty' "${CONFIG}")"
[[ "${CONFIG_DOMAIN}" == "${DOMAIN}" ]] || \
  fail "vms.ui.public_endpoint.hostname must be ${DOMAIN}, got ${CONFIG_DOMAIN:-<empty>}"

ACME_EMAIL="$(jq -r '.vms.ui.public_endpoint.acme_email // empty' "${CONFIG}")"
[[ -n "${ACME_EMAIL}" && "${ACME_EMAIL}" != *@example.com ]] || \
  fail "Set a real vms.ui.public_endpoint.acme_email before deployment."

jq -e '.vms.ui.role == "ui" and .vms.ui.assign_public_ip == true' "${CONFIG}" >/dev/null || \
  fail "vms.ui must have role ui and assign_public_ip=true."

jq -e '.network.ui_public_ports | index(443) != null' "${CONFIG}" >/dev/null || \
  fail "network.ui_public_ports must include 443 for HTTPS."

python3 - "${CONFIG}" <<'PY'
import ipaddress
import json
import sys

with open(sys.argv[1], encoding="utf-8") as config_file:
    config = json.load(config_file)

networks = {}
for cloud in {vm.get("cloud", config["default_cloud"]).lower() for vm in config["vms"].values()}:
    networks[cloud] = config["network"] | config["clouds"].get(cloud, {}).get("network", {})

for name, vm in config["vms"].items():
    cloud = vm.get("cloud", config["default_cloud"]).lower()
    network = networks[cloud]
    if vm["role"] == "bastion":
        subnet_key = "management_subnet_cidr"
    elif cloud == "aws" and vm["assign_public_ip"]:
        subnet_key = "public_subnet_cidr"
    else:
        subnet_key = "workload_subnet_cidr"

    address = ipaddress.ip_address(vm["internal_ip"])
    subnet = ipaddress.ip_network(network[subnet_key])
    if address not in subnet:
        raise SystemExit(
            f"VM {name} uses {cloud} and must have an internal_ip inside "
            f"{subnet_key} ({subnet}), got {address}"
        )

for cloud, network in networks.items():
    ranges = {
        key: ipaddress.ip_network(value)
        for key, value in network.items()
        if key.endswith("_cidr")
    }
    ranges.update({
        f"database_subnet_cidrs[{index}]": ipaddress.ip_network(value)
        for index, value in enumerate(network.get("database_subnet_cidrs", []))
    })
    items = list(ranges.items())
    for index, (left_name, left) in enumerate(items):
        for right_name, right in items[index + 1:]:
            if left_name == "vpc_cidr" or right_name == "vpc_cidr":
                continue
            if left.overlaps(right):
                raise SystemExit(
                    f"Cloud {cloud} network ranges overlap: {left_name}={left} and "
                    f"{right_name}={right}"
                )

if len(networks) > 1:
    cloud_items = list(networks.items())
    for index, (left_cloud, left_network) in enumerate(cloud_items):
        left_vpc = ipaddress.ip_network(left_network["vpc_cidr"])
        for right_cloud, right_network in cloud_items[index + 1:]:
            right_vpc = ipaddress.ip_network(right_network["vpc_cidr"])
            if left_vpc.overlaps(right_vpc):
                raise SystemExit(
                    f"Mixed-cloud VPC CIDRs overlap: {left_cloud}={left_vpc}, "
                    f"{right_cloud}={right_vpc}"
                )
PY

USED_CLOUDS="$(jq -r '
  . as $config
  | [.vms[] | (.cloud // $config.default_cloud | ascii_downcase)]
  | unique[]
' "${CONFIG}")"

MANAGE_DB="$(jq -r '.manage_db' "${CONFIG}")"
required_roles=(history fetcher ui)
if [[ "${MANAGE_DB}" == false ]]; then
  required_roles=(database "${required_roles[@]}")
fi

for required_role in "${required_roles[@]}"; do
  ROLE_COUNT="$(jq -r --arg role "${required_role}" \
    '[.vms[] | select(.role == $role)] | length' "${CONFIG}")"
  [[ "${ROLE_COUNT}" -eq 1 ]] || \
    fail "Project config must define exactly one VM with role ${required_role}."
done

if [[ "${MANAGE_DB}" == true ]]; then
  DATABASE_VM_COUNT="$(jq '[.vms[] | select(.role == "database")] | length' "${CONFIG}")"
  [[ "${DATABASE_VM_COUNT}" -eq 0 ]] || fail \
    "manage_db=true must not define a VM with role database."
else
  jq -e 'has("database") | not' "${CONFIG}" >/dev/null || fail \
    "manage_db=false must not define the managed database object."
fi

while IFS= read -r cloud; do
  [[ -n "${cloud}" ]] || continue
  BASTION_COUNT="$(jq -r --arg cloud "${cloud}" '
    . as $config
    | [.vms[] | select(
        .role == "bastion"
        and ((.cloud // $config.default_cloud | ascii_downcase) == $cloud)
      )]
    | length
  ' "${CONFIG}")"
  PRIVATE_COUNT="$(jq -r --arg cloud "${cloud}" '
    . as $config
    | [.vms[] | select(
        .role != "bastion"
        and .assign_public_ip == false
        and ((.cloud // $config.default_cloud | ascii_downcase) == $cloud)
      )]
    | length
  ' "${CONFIG}")"
  if [[ "${PRIVATE_COUNT}" -gt 0 && "${BASTION_COUNT}" -ne 1 ]]; then
    fail "Cloud ${cloud} has private workloads and must have exactly one bastion."
  fi
done <<< "${USED_CLOUDS}"

MISSING_SECRETS=""
while IFS= read -r variable_name; do
  [[ -n "${variable_name}" ]] || continue
  if [[ -z "$(printenv "${variable_name}" 2>/dev/null || true)" ]]; then
    if [[ -t 0 ]]; then
      printf 'Enter value for %s: ' "${variable_name}" >&2
      IFS= read -r -s secret_value
      printf '\n' >&2
      [[ -n "${secret_value}" ]] || fail "${variable_name} cannot be empty."
      printf -v "${variable_name}" '%s' "${secret_value}"
      export "${variable_name?}"
      unset secret_value
    else
      MISSING_SECRETS="${MISSING_SECRETS}${MISSING_SECRETS:+, }${variable_name}"
    fi
  fi
done < <(jq -r '
  [.secrets_by_role[].[]?]
  | unique[]
  | ascii_upcase
  | gsub("[^A-Z0-9]"; "_")
' "${CONFIG}")
[[ -z "${MISSING_SECRETS}" ]] || fail "Missing secret environment variables: ${MISSING_SECRETS}"

if [[ "${MANAGE_DB}" == true ]]; then
  DATABASE_SECRET_ID="$(jq -r '.database.password_secret_id' "${CONFIG}")"
  DATABASE_SECRET_ENV="$(printf '%s' "${DATABASE_SECRET_ID}" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9' '_')"
  DATABASE_SECRET_ENV="${DATABASE_SECRET_ENV%_}"
  DATABASE_PASSWORD="${!DATABASE_SECRET_ENV:-}"
  [[ -n "${DATABASE_PASSWORD}" ]] || fail \
    "${DATABASE_SECRET_ENV} is required for managed PostgreSQL."
  jq -e --arg secret_id "${DATABASE_SECRET_ID}" '
    [.secrets_by_role.history.POSTGRES_PASSWORD,
     .secrets_by_role.fetcher.POSTGRES_PASSWORD,
     .secrets_by_role.ui.POSTGRES_PASSWORD]
    | all(. == $secret_id)
  ' "${CONFIG}" >/dev/null || fail \
    "Managed PostgreSQL requires history, fetcher, and ui to use database.password_secret_id."
  export TF_VAR_database_password="${DATABASE_PASSWORD}"
  unset DATABASE_PASSWORD
fi

export OILSCOPE_PROJECT_CONFIG="${CONFIG}"
if [[ -z "${OILSCOPE_SSH_USER:-}" ]]; then
  OILSCOPE_SSH_USER="$(jq -r '.ssh_users | keys | first' "${CONFIG}")"
  export OILSCOPE_SSH_USER
fi

while IFS= read -r cloud; do
  [[ -n "${cloud}" ]] || continue
  case "${cloud}" in
    gcp)
      require_command gcloud
      gcloud auth application-default print-access-token >/dev/null
      ;;
    aws)
      require_command aws
      aws sts get-caller-identity >/dev/null
      ;;
    *)
      fail "Unsupported cloud: ${cloud}"
      ;;
  esac

  SSH_KEY="${OILSCOPE_SSH_KEY:-}"
  if [[ -z "${SSH_KEY}" ]]; then
    if [[ "${cloud}" == "gcp" ]]; then
      SSH_KEY="${OILSCOPE_GCP_SSH_KEY:-${HOME}/.ssh/google_compute_engine}"
    else
      SSH_KEY="${OILSCOPE_AWS_SSH_KEY:-${HOME}/.ssh/id_ed25519}"
    fi
  fi
  [[ -f "${SSH_KEY}" ]] || fail \
    "SSH private key for ${cloud} not found: ${SSH_KEY}. Set OILSCOPE_SSH_KEY or the cloud-specific key variable."
done <<< "${USED_CLOUDS}"

if [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
  if [[ -t 0 ]]; then
    printf 'Enter CLOUDFLARE_API_TOKEN: ' >&2
    IFS= read -r -s CLOUDFLARE_API_TOKEN
    printf '\n' >&2
    export CLOUDFLARE_API_TOKEN
  else
    fail "CLOUDFLARE_API_TOKEN is required to point ${DOMAIN} to the UI VM."
  fi
fi
[[ -n "${CLOUDFLARE_API_TOKEN}" ]] || fail "CLOUDFLARE_API_TOKEN cannot be empty."

TF_APPLY_ARGS=(
  -var="project_config_path=${CONFIG}"
)
if [[ "${OILSCOPE_AUTO_APPROVE:-0}" == "1" ]]; then
  TF_APPLY_ARGS+=(-auto-approve)
fi

step "Preparing an isolated Ansible environment"
if [[ ! -x "${DEPLOY_VENV}/bin/python" ]]; then
  python3 -m venv "${DEPLOY_VENV}"
fi
"${DEPLOY_VENV}/bin/python" -m pip install \
  'ansible-core>=2.17,<2.21' \
  -r "${ANSIBLE_DIR}/requirements.txt"

readonly ANSIBLE_GALAXY="${DEPLOY_VENV}/bin/ansible-galaxy"
readonly ANSIBLE_INVENTORY="${DEPLOY_VENV}/bin/ansible-inventory"
readonly ANSIBLE_PLAYBOOK="${DEPLOY_VENV}/bin/ansible-playbook"

if locale -a 2>/dev/null | grep -Eiq '^en_US\.UTF-?8$'; then
  export LANG=en_US.UTF-8
  export LC_ALL=en_US.UTF-8
elif locale -a 2>/dev/null | grep -Eiq '^C\.UTF-?8$'; then
  export LANG=C.UTF-8
  export LC_ALL=C.UTF-8
fi

step "Installing required Ansible collections"
"${ANSIBLE_GALAXY}" collection install -r "${ANSIBLE_DIR}/requirements.yml"

COLLECTION_BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/oilscope-collection.XXXXXX")"
BOOTSTRAP_ENABLED=false
cleanup() {
  if [[ "${BOOTSTRAP_ENABLED}" == true ]]; then
    printf '\n==> Closing temporary bastion SSH port 22 after an interrupted deployment\n' >&2
    terraform -chdir="${TF_RUN_DIR}" apply \
      -input=false \
      -auto-approve \
      -var="project_config_path=${CONFIG}" \
      -var="enable_bastion_ssh_bootstrap=false" >/dev/null || \
      printf 'WARNING: Could not close the temporary SSH bootstrap rule automatically.\n' >&2
  fi
  find "${COLLECTION_BUILD_DIR}" -type f -delete 2>/dev/null || true
  rmdir "${COLLECTION_BUILD_DIR}" 2>/dev/null || true
}
trap cleanup EXIT

"${ANSIBLE_GALAXY}" collection build "${COLLECTION_DIR}" \
  --output-path "${COLLECTION_BUILD_DIR}" \
  --force
COLLECTION_ARCHIVE="$(find "${COLLECTION_BUILD_DIR}" -maxdepth 1 -type f -name 'oilscope-platform-*.tar.gz' -print -quit)"
[[ -n "${COLLECTION_ARCHIVE}" ]] || fail "Failed to build the local oilscope.platform collection."
"${ANSIBLE_GALAXY}" collection install "${COLLECTION_ARCHIVE}" --force

step "Initializing Terraform"
mkdir -p "${TF_STATE_DIR}"
terraform -chdir="${TF_RUN_DIR}" init -reconfigure \
  -backend-config="path=${TF_STATE_PATH}"

step "Creating cloud infrastructure with temporary SSH bootstrap access"
terraform -chdir="${TF_RUN_DIR}" apply \
  "${TF_APPLY_ARGS[@]}" \
  -var="enable_bastion_ssh_bootstrap=true"
BOOTSTRAP_ENABLED=true

DATABASE_VARS_FILE="${COLLECTION_BUILD_DIR}/database-connection.json"
terraform -chdir="${TF_RUN_DIR}" output -json managed_database | \
  jq '{managed_database: .}' > "${DATABASE_VARS_FILE}"
chmod 0600 "${DATABASE_VARS_FILE}"

UI_IP="$(terraform -chdir="${TF_RUN_DIR}" output -json workload_external_ips | jq -r '.ui // empty')"
[[ "${UI_IP}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
  fail "Terraform did not return a public IPv4 address for the ui VM."

step "Updating Cloudflare DNS for ${DOMAIN} -> ${UI_IP}"
CF_API="https://api.cloudflare.com/client/v4"
CF_AUTH=(-H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json")
ZONE_RESPONSE="$(curl --fail --silent --show-error "${CF_AUTH[@]}" \
  "${CF_API}/zones?name=${DOMAIN}&status=active")"
ZONE_ID="$(jq -r '.result[0].id // empty' <<< "${ZONE_RESPONSE}")"
[[ -n "${ZONE_ID}" ]] || fail "Cloudflare zone ${DOMAIN} was not found for this API token."

RECORD_RESPONSE="$(curl --fail --silent --show-error "${CF_AUTH[@]}" \
  "${CF_API}/zones/${ZONE_ID}/dns_records?type=A&name=${DOMAIN}")"
RECORD_ID="$(jq -r '.result[0].id // empty' <<< "${RECORD_RESPONSE}")"
DNS_PAYLOAD="$(jq -cn --arg name "${DOMAIN}" --arg content "${UI_IP}" \
  '{type:"A", name:$name, content:$content, ttl:60, proxied:false}')"

if [[ -n "${RECORD_ID}" ]]; then
  DNS_RESPONSE="$(curl --fail --silent --show-error --request PUT "${CF_AUTH[@]}" \
    --data "${DNS_PAYLOAD}" \
    "${CF_API}/zones/${ZONE_ID}/dns_records/${RECORD_ID}")"
else
  DNS_RESPONSE="$(curl --fail --silent --show-error --request POST "${CF_AUTH[@]}" \
    --data "${DNS_PAYLOAD}" \
    "${CF_API}/zones/${ZONE_ID}/dns_records")"
fi
jq -e '.success == true' <<< "${DNS_RESPONSE}" >/dev/null || \
  fail "Cloudflare rejected the DNS update: $(jq -c '.errors' <<< "${DNS_RESPONSE}")"

step "Waiting for public DNS propagation"
DNS_READY=false
for _ in $(seq 1 60); do
  if dig +short A "${DOMAIN}" @1.1.1.1 | grep -Fxq "${UI_IP}"; then
    DNS_READY=true
    break
  fi
  sleep 10
done
[[ "${DNS_READY}" == true ]] || fail "${DOMAIN} did not resolve to ${UI_IP} within 10 minutes."

step "Waiting for bastion SSH bootstrap ports"
BASTION_OUTPUT="$(terraform -chdir="${TF_RUN_DIR}" output -json vms | jq -r \
  --slurpfile config "${CONFIG}" '
  to_entries[] as $entry
  | select($entry.value.role == "bastion")
  | [
      $entry.value.cloud,
      $entry.key,
      $entry.value.public_ip,
      ($config[0].vms[$entry.key].ssh_port // 22)
    ]
  | @tsv
')"
BASTION_CONNECTIONS=""
while IFS=$'\t' read -r bastion_cloud bastion_key bastion_ip final_port; do
  [[ -n "${bastion_cloud}" && -n "${bastion_key}" && -n "${bastion_ip}" ]] || continue
  SSH_READY=false
  CONNECT_PORT=""
  for _ in $(seq 1 60); do
    if nc -z -w 3 "${bastion_ip}" 22 >/dev/null 2>&1; then
      CONNECT_PORT=22
      SSH_READY=true
      break
    fi
    if nc -z -w 3 "${bastion_ip}" "${final_port}" >/dev/null 2>&1; then
      CONNECT_PORT="${final_port}"
      SSH_READY=true
      break
    fi
    sleep 10
  done
  [[ "${SSH_READY}" == true ]] || fail \
    "SSH did not open on ${bastion_key} (${bastion_ip}, ports 22/${final_port})."
  BASTION_CONNECTIONS="${BASTION_CONNECTIONS}${bastion_cloud}"$'\t'"${CONNECT_PORT}"$'\n'
done <<< "${BASTION_OUTPUT}"

step "Discovering cloud instances"
"${ANSIBLE_INVENTORY}" -i "${INVENTORY}" --graph

step "Configuring bastion SSH"
while IFS=$'\t' read -r bastion_cloud connect_port; do
  [[ -n "${bastion_cloud}" && -n "${connect_port}" ]] || continue
  OILSCOPE_BASTION_CONNECT_PORT="${connect_port}" "${ANSIBLE_PLAYBOOK}" \
    oilscope.platform.bootstrap_bastion \
    -i "${INVENTORY}" \
    -e "project_config_path=${CONFIG}" \
    --limit "${bastion_cloud}_bastion"
done <<< "${BASTION_CONNECTIONS}"

step "Removing temporary SSH bootstrap access"
terraform -chdir="${TF_RUN_DIR}" apply \
  "${TF_APPLY_ARGS[@]}" \
  -var="enable_bastion_ssh_bootstrap=false"
BOOTSTRAP_ENABLED=false

step "Uploading application secrets"
"${ANSIBLE_PLAYBOOK}" oilscope.platform.upload_secret_versions \
  -e "secret_versions_config_file=${CONFIG}" \
  --check
"${ANSIBLE_PLAYBOOK}" oilscope.platform.upload_secret_versions \
  -e "secret_versions_config_file=${CONFIG}"

step "Deploying database, history, fetcher, UI, and HTTPS proxy"
"${ANSIBLE_PLAYBOOK}" oilscope.platform.deploy_workloads \
  -i "${INVENTORY}" \
  -e "project_config_path=${CONFIG}" \
  -e "@${DATABASE_VARS_FILE}"

step "Waiting for a trusted HTTPS response"
HTTPS_READY=false
for _ in $(seq 1 60); do
  if curl --fail --silent --show-error --max-time 10 "https://${DOMAIN}/" >/dev/null; then
    HTTPS_READY=true
    break
  fi
  sleep 10
done
[[ "${HTTPS_READY}" == true ]] || \
  fail "https://${DOMAIN}/ did not return a valid trusted HTTPS response within 10 minutes."

printf '\nDeployment completed: https://%s/\n' "${DOMAIN}"
