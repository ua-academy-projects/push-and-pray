#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/configure-ansible.sh [--preflight-only]

Builds and installs the local oilscope.platform collection, validates dynamic
inventory and SSH access, bootstraps the bastion when it is still reachable on
port 22, and deploys all workloads in dependency order.

Environment variables:
  OILSCOPE_PROJECT_CONFIG  Project JSON (default: infrastructure/terraform/config/dev.json)
  OILSCOPE_SSH_KEY         Private SSH key override (auto-detected by default)
  OILSCOPE_ANSIBLE_VENV    Python venv override (default: ~/.venvs/oilscope-ansible)
  OILSCOPE_SSH_USER        Optional SSH user override
  AWS_PROFILE              Optional named AWS CLI profile
  GOOGLE_CLOUD_PROJECT     Required only when the configuration selects GCP
EOF
}

preflight_only=false
case "${1:-}" in
  "") ;;
  --preflight-only) preflight_only=true ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
inventory_path="${repo_root}/infrastructure/ansible/inventory/oilscope.yml"
collection_source="${repo_root}/infrastructure/ansible/oilscope/platform"
collections_root="${repo_root}/.ansible/collections"
ansible_local_temp="${TMPDIR:-/tmp}/oilscope-ansible-${UID}"
config_path="${OILSCOPE_PROJECT_CONFIG:-${repo_root}/infrastructure/terraform/config/dev.json}"
ansible_venv="${OILSCOPE_ANSIBLE_VENV:-${HOME}/.venvs/oilscope-ansible}"

if [[ -x "${ansible_venv}/bin/ansible-playbook" ]]; then
  export PATH="${ansible_venv}/bin:${PATH}"
fi

if [[ -n "${OILSCOPE_SSH_KEY:-}" ]]; then
  ssh_key="${OILSCOPE_SSH_KEY}"
else
  ssh_key=""
  for key_candidate in \
    "${HOME}/.ssh/terraform-access" \
    "${HOME}/.ssh/terraform_ed25519" \
    "${HOME}/.ssh/google_compute_engine"; do
    if [[ -f "${key_candidate}" ]]; then
      ssh_key="${key_candidate}"
      break
    fi
  done
fi

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

step() {
  printf '\n==> %s\n' "$*"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command is missing: $1"
}

require_command ansible
require_command ansible-galaxy
require_command ansible-inventory
require_command ansible-playbook
require_command python3

if ! python3 -c 'import boto3, botocore, google.auth, requests' >/dev/null 2>&1; then
  fail "Ansible Python dependencies are missing. Activate ${ansible_venv} or set OILSCOPE_ANSIBLE_VENV."
fi

[[ -f "${config_path}" ]] || fail "Project configuration was not found: ${config_path}"
[[ -f "${inventory_path}" ]] || fail "Inventory was not found: ${inventory_path}"
[[ -n "${ssh_key}" && -f "${ssh_key}" ]] || \
  fail "SSH private key was not found; set OILSCOPE_SSH_KEY to its absolute path."

config_path="$(readlink -f -- "${config_path}")"
ssh_key="$(readlink -f -- "${ssh_key}")"

export OILSCOPE_PROJECT_CONFIG="${config_path}"
export OILSCOPE_SSH_KEY="${ssh_key}"
export ANSIBLE_COLLECTIONS_PATH="${collections_root}:${HOME}/.ansible/collections:/usr/share/ansible/collections"
export ANSIBLE_LOCAL_TEMP="${ansible_local_temp}"
mkdir -p "${ANSIBLE_LOCAL_TEMP}"

step "Validating the project JSON"
python3 -m json.tool "${config_path}" >/dev/null

registry_username="$({
  python3 - "${config_path}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as config_file:
    print(json.load(config_file).get("registry", {}).get("username", ""))
PY
} | tr -d '\r\n')"

if [[ -z "${registry_username}" || "${registry_username}" == replace-* ]]; then
  fail "Set registry.username in ${config_path} to the GitHub account that owns the GHCR token."
fi

selected_clouds="$({
  python3 - "${config_path}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as config_file:
    config = json.load(config_file)

default_cloud = config["default_cloud"]
print("\n".join(sorted({vm.get("cloud", default_cloud) for vm in config["vms"].values()})))
PY
})"

if grep -qx aws <<<"${selected_clouds}"; then
  require_command aws
  step "Checking AWS credentials"
  aws sts get-caller-identity >/dev/null
fi

if grep -qx gcp <<<"${selected_clouds}"; then
  require_command gcloud
  step "Checking Google Application Default Credentials"
  gcloud auth application-default print-access-token >/dev/null
fi

step "Building and installing the repository's Ansible collection"
mkdir -p "${collections_root}"
collection_build_dir="$(mktemp -d)"
cleanup() {
  rm -rf -- "${collection_build_dir}"
}
trap cleanup EXIT

ansible-galaxy collection build "${collection_source}" \
  --output-path "${collection_build_dir}" \
  --force >/dev/null

collection_package="$(find "${collection_build_dir}" -maxdepth 1 -type f -name 'oilscope-platform-*.tar.gz' -print -quit)"
[[ -n "${collection_package}" ]] || fail "The oilscope.platform collection package was not produced."

ansible-galaxy collection install "${collection_package}" \
  --collections-path "${collections_root}" \
  --force >/dev/null

ansible_args=(
  -i "${inventory_path}"
  -e "project_config_path=${config_path}"
)

step "Loading dynamic inventory"
inventory_snapshot="${collection_build_dir}/inventory.json"
ansible-inventory "${ansible_args[@]}" --list >"${inventory_snapshot}"

inventory_counts="$({
  python3 - "${inventory_snapshot}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as inventory_file:
    inventory = json.load(inventory_file)

hostvars = inventory.get("_meta", {}).get("hostvars", {})
bastion = inventory.get("bastion", {}).get("hosts", [])
workloads = inventory.get("workloads", {}).get("hosts", [])
print(len(hostvars), len(bastion), len(workloads))
PY
})"
read -r inventory_hosts bastion_hosts workload_hosts <<<"${inventory_counts}"

[[ "${inventory_hosts}" -gt 0 ]] || fail "Dynamic inventory returned no hosts."
[[ "${bastion_hosts}" -eq 1 ]] || fail "Dynamic inventory must contain exactly one bastion host."
[[ "${workload_hosts}" -gt 0 ]] || fail "Dynamic inventory returned no workload hosts."

ansible-inventory "${ansible_args[@]}" --graph
printf 'Discovered %s hosts: %s bastion and %s workloads.\n' \
  "${inventory_hosts}" "${bastion_hosts}" "${workload_hosts}"

step "Checking the bastion SSH connection"
if ansible bastion "${ansible_args[@]}" -m ansible.builtin.ping; then
  printf 'Bastion already accepts connections on its configured SSH port.\n'
else
  printf 'Configured bastion port is unavailable; checking bootstrap port 22.\n'
  if ! OILSCOPE_BASTION_CONNECT_PORT=22 \
    ansible bastion "${ansible_args[@]}" -m ansible.builtin.ping; then
    fail "Bastion is unavailable on both its configured port and bootstrap port 22."
  fi

  step "Configuring the bastion and switching it to the final SSH port"
  OILSCOPE_BASTION_CONNECT_PORT=22 \
    ansible-playbook oilscope.platform.bootstrap_bastion "${ansible_args[@]}"
fi

step "Checking SSH access to workload VMs through the bastion"
ansible workloads "${ansible_args[@]}" -m ansible.builtin.ping

if grep -qx aws <<<"${selected_clouds}"; then
  step "Checking outbound HTTPS from private AWS workloads through the NAT Gateway"
  ansible 'cloud_aws:&workloads:!ui' "${ansible_args[@]}" \
    -m ansible.builtin.uri \
    -a 'url=https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb method=HEAD status_code=200 timeout=20'
fi

if [[ "${preflight_only}" == true ]]; then
  printf '\nPreflight completed successfully; no workload configuration was changed.\n'
  exit 0
fi

step "Deploying monitoring agents and application workloads"
ansible-playbook oilscope.platform.deploy_workloads "${ansible_args[@]}"

step "Checking running containers on every workload"
ansible workloads "${ansible_args[@]}" \
  --become \
  -m ansible.builtin.command \
  -a 'docker ps'

printf '\nAnsible configuration completed successfully.\n'
