#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
readonly REPO_ROOT
readonly GENERATED_ROOT="${OILSCOPE_GENERATED_ROOT:-${REPO_ROOT}/.generated}"

PROVIDER=""
ENVIRONMENT=""
DEPLOYMENT=""
REGION=""
CONFIG_INPUT=""
MODE="check"

usage() {
  cat <<'EOF'
Usage:
  scripts/bootstrap-cloud.sh \
    --provider aws|gcp \
    --environment dev|stage|prod \
    --deployment NAME \
    --region REGION \
    --config PATH \
    [--check|--dry-run|--yes]

The default mode is --check and never changes cloud or local state.
--dry-run is an alias of --check. --yes performs the documented additive
foundation changes and writes backend.hcl/foundation.json under .generated/.
EOF
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

info() {
  printf 'INFO: %s\n' "$*"
}

action() {
  printf 'ACTION: %s\n' "$*"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

while (($# > 0)); do
  case "$1" in
    --provider)
      PROVIDER="${2:-}"
      shift 2
      ;;
    --environment)
      ENVIRONMENT="${2:-}"
      shift 2
      ;;
    --deployment)
      DEPLOYMENT="${2:-}"
      shift 2
      ;;
    --region)
      REGION="${2:-}"
      shift 2
      ;;
    --config)
      CONFIG_INPUT="${2:-}"
      shift 2
      ;;
    --check|--dry-run)
      MODE="check"
      shift
      ;;
    --yes)
      MODE="apply"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[[ "${PROVIDER}" == "aws" || "${PROVIDER}" == "gcp" ]] || \
  fail "--provider must be aws or gcp."
[[ "${ENVIRONMENT}" =~ ^(dev|stage|prod)$ ]] || \
  fail "--environment must be dev, stage, or prod."
[[ "${DEPLOYMENT}" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]] || \
  fail "--deployment must use lowercase letters, digits, and hyphens."
[[ -n "${REGION}" ]] || fail "--region is required."
[[ -n "${CONFIG_INPUT}" ]] || fail "--config is required."

require_command jq
require_command terraform
require_command python3
if [[ "${PROVIDER}" == "aws" ]]; then
  require_command aws
else
  require_command gcloud
fi

CONFIG_DIR="$(cd "$(dirname "${CONFIG_INPUT}")" && pwd -P)"
CONFIG="${CONFIG_DIR}/$(basename "${CONFIG_INPUT}")"
readonly CONFIG
[[ -f "${CONFIG}" ]] || fail "Project config not found: ${CONFIG}"
jq empty "${CONFIG}"
python3 "${SCRIPT_DIR}/validate_project_config.py" "${CONFIG}"

CONFIG_PROVIDER="$(jq -r '.cloud_provider // .default_cloud // empty | ascii_downcase' "${CONFIG}")"
CONFIG_ENVIRONMENT="$(jq -r '.environment // empty' "${CONFIG}")"
CONFIG_DEPLOYMENT="$(jq -r '.name_prefix // empty' "${CONFIG}")"
LOCATION_PROFILE="$(jq -r '.defaults.location_profile // empty' "${CONFIG}")"
CONFIG_REGION="$(jq -r --arg provider "${PROVIDER}" --arg profile "${LOCATION_PROFILE}" \
  '.clouds[$provider].locations[$profile].region // empty' "${CONFIG}")"
CONFIG_RUNTIME="$(jq -r '.deployment_runtime // "compose" | ascii_downcase' "${CONFIG}")"

[[ "${CONFIG_PROVIDER}" == "${PROVIDER}" ]] || \
  fail "Config provider ${CONFIG_PROVIDER:-<missing>} does not match --provider ${PROVIDER}."
[[ "${CONFIG_ENVIRONMENT}" == "${ENVIRONMENT}" ]] || \
  fail "Config environment ${CONFIG_ENVIRONMENT:-<missing>} does not match --environment ${ENVIRONMENT}."
[[ "${CONFIG_DEPLOYMENT}" == "${DEPLOYMENT}" ]] || \
  fail "Config name_prefix ${CONFIG_DEPLOYMENT:-<missing>} does not match --deployment ${DEPLOYMENT}."
[[ "${CONFIG_REGION}" == "${REGION}" ]] || \
  fail "Config region ${CONFIG_REGION:-<missing>} does not match --region ${REGION}."
[[ "${CONFIG_RUNTIME}" == "compose" ]] || \
  fail "Only deployment_runtime=compose is implemented."

TF_VERSION="$(terraform version -json | jq -r '.terraform_version')"
python3 - "${TF_VERSION}" <<'PY'
import sys

parts = tuple(int(part) for part in sys.argv[1].split(".")[:2])
if parts < (1, 10):
    raise SystemExit("Terraform 1.10 or newer is required for native S3 lockfiles.")
PY

readonly OUTPUT_DIR="${GENERATED_ROOT}/${ENVIRONMENT}/${PROVIDER}/${DEPLOYMENT}"
readonly BACKEND_FILE="${OUTPUT_DIR}/backend.hcl"
readonly MANIFEST_FILE="${OUTPUT_DIR}/foundation.json"

write_generated_files_safe() {
  local manifest_json="$1"
  local backend_content="$2"

  install -d -m 0700 "${OUTPUT_DIR}"
  umask 077
  printf '%s\n' "${backend_content}" >"${BACKEND_FILE}"
  printf '%s\n' "${manifest_json}" >"${MANIFEST_FILE}"
  chmod 0600 "${BACKEND_FILE}" "${MANIFEST_FILE}"
}

aws_role_exists() {
  aws iam get-role --role-name "$1" >/dev/null 2>&1
}

aws_ensure_role() {
  local role_name="$1"
  local trust_file="$2"

  if aws_role_exists "${role_name}"; then
    info "AWS IAM role exists: ${role_name}"
  else
    action "Creating AWS IAM role ${role_name}"
    aws iam create-role \
      --role-name "${role_name}" \
      --assume-role-policy-document "file://${trust_file}" \
      --description "OilScope ${role_name} foundation identity" \
      --tags Key=application,Value="${DEPLOYMENT}" Key=environment,Value="${ENVIRONMENT}" \
      >/dev/null
  fi
  aws iam update-assume-role-policy \
    --role-name "${role_name}" \
    --policy-document "file://${trust_file}"
}

bootstrap_aws() {
  local identity account arn trusted_principal bucket state_key
  local terraform_role ci_role runtime_role github_repository oidc_arn
  local bucket_exists=false missing=0

  identity="$(aws sts get-caller-identity --output json)"
  account="$(jq -r '.Account' <<<"${identity}")"
  arn="$(jq -r '.Arn' <<<"${identity}")"
  [[ -n "${account}" && "${account}" != "null" ]] || fail "Unable to resolve AWS account."
  [[ -n "${arn}" && "${arn}" != "null" ]] || fail "Unable to resolve AWS principal."

  trusted_principal="${arn}"
  if [[ "${arn}" =~ ^arn:aws:sts::([0-9]+):assumed-role/([^/]+)/ ]]; then
    trusted_principal="arn:aws:iam::${BASH_REMATCH[1]}:role/${BASH_REMATCH[2]}"
  fi

  bucket="${DEPLOYMENT}-${ENVIRONMENT}-${account}-tfstate"
  state_key="${ENVIRONMENT}/${PROVIDER}/${DEPLOYMENT}/terraform.tfstate"
  terraform_role="${DEPLOYMENT}-${ENVIRONMENT}-terraform"
  ci_role="${DEPLOYMENT}-${ENVIRONMENT}-ci-publisher"
  runtime_role="${DEPLOYMENT}-${ENVIRONMENT}-runtime"
  github_repository="$(jq -r '.registry.repository // empty' "${CONFIG}" | sed -E 's#^ghcr.io/([^/]+/[^/]+).*$#\1#')"
  [[ "${github_repository}" == */* ]] || fail "registry.repository must identify a GitHub owner/repository."

  info "AWS target account=${account} region=${REGION} principal=${arn}"
  info "State bucket=${bucket} key=${state_key}"

  if aws s3api head-bucket --bucket "${bucket}" >/dev/null 2>&1; then
    bucket_exists=true
    info "AWS state bucket exists: ${bucket}"
  else
    action "AWS state bucket is missing: ${bucket}"
    ((missing += 1))
  fi
  for role in "${terraform_role}" "${ci_role}" "${runtime_role}"; do
    if aws_role_exists "${role}"; then
      info "AWS IAM role exists: ${role}"
    else
      action "AWS IAM role is missing: ${role}"
      ((missing += 1))
    fi
  done

  if [[ "${MODE}" == "check" ]]; then
    info "Check complete: ${missing} documented AWS foundation object(s) missing. No changes made."
    return 0
  fi

  info "Mutation authorised by --yes for account=${account} region=${REGION}."
  if [[ "${bucket_exists}" == false ]]; then
    if [[ "${REGION}" == "us-east-1" ]]; then
      aws s3api create-bucket --bucket "${bucket}" --region "${REGION}" >/dev/null
    else
      aws s3api create-bucket \
        --bucket "${bucket}" \
        --region "${REGION}" \
        --create-bucket-configuration "LocationConstraint=${REGION}" \
        >/dev/null
    fi
  fi
  aws s3api put-public-access-block \
    --bucket "${bucket}" \
    --public-access-block-configuration \
      BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
  aws s3api put-bucket-versioning \
    --bucket "${bucket}" \
    --versioning-configuration Status=Enabled
  aws s3api put-bucket-encryption \
    --bucket "${bucket}" \
    --server-side-encryption-configuration \
      '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}'

  local temp_dir human_trust github_trust runtime_trust terraform_policy ci_policy runtime_policy
  temp_dir="$(mktemp -d)"
  trap 'rm -R -- "${temp_dir}"' EXIT
  human_trust="${temp_dir}/human-trust.json"
  github_trust="${temp_dir}/github-trust.json"
  runtime_trust="${temp_dir}/runtime-trust.json"
  terraform_policy="${temp_dir}/terraform-policy.json"
  ci_policy="${temp_dir}/ci-policy.json"
  runtime_policy="${temp_dir}/runtime-policy.json"

  jq -n --arg principal "${trusted_principal}" '{
    Version:"2012-10-17",
    Statement:[{Effect:"Allow",Principal:{AWS:$principal},Action:"sts:AssumeRole"}]
  }' >"${human_trust}"
  aws_ensure_role "${terraform_role}" "${human_trust}"

  oidc_arn="arn:aws:iam::${account}:oidc-provider/token.actions.githubusercontent.com"
  if ! aws iam list-open-id-connect-providers --output json \
    | jq -e --arg arn "${oidc_arn}" '.OpenIDConnectProviderList[]? | select(.Arn == $arn)' \
      >/dev/null; then
    action "Creating GitHub Actions OIDC provider"
    aws iam create-open-id-connect-provider \
      --url https://token.actions.githubusercontent.com \
      --client-id-list sts.amazonaws.com \
      --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 \
      >/dev/null
  fi
  jq -n --arg oidc "${oidc_arn}" --arg repo "repo:${github_repository}:*" '{
    Version:"2012-10-17",
    Statement:[{
      Effect:"Allow",
      Principal:{Federated:$oidc},
      Action:"sts:AssumeRoleWithWebIdentity",
      Condition:{
        StringEquals:{"token.actions.githubusercontent.com:aud":"sts.amazonaws.com"},
        StringLike:{"token.actions.githubusercontent.com:sub":$repo}
      }
    }]
  }' >"${github_trust}"
  aws_ensure_role "${ci_role}" "${github_trust}"

  jq -n '{
    Version:"2012-10-17",
    Statement:[{Effect:"Allow",Principal:{Service:"ec2.amazonaws.com"},Action:"sts:AssumeRole"}]
  }' >"${runtime_trust}"
  aws_ensure_role "${runtime_role}" "${runtime_trust}"

  jq -n --arg bucket "${bucket}" --arg prefix "${DEPLOYMENT}-${ENVIRONMENT}" '{
    Version:"2012-10-17",
    Statement:[
      {Sid:"StateBucket",Effect:"Allow",Action:["s3:ListBucket","s3:GetBucketVersioning"],Resource:("arn:aws:s3:::"+$bucket)},
      {Sid:"StateObjects",Effect:"Allow",Action:["s3:GetObject","s3:PutObject","s3:DeleteObject"],Resource:("arn:aws:s3:::"+$bucket+"/*")},
      {Sid:"WorkloadServices",Effect:"Allow",Action:["ec2:*","rds:*","ecr:*","secretsmanager:*","ssm:*","logs:*","cloudwatch:*","synthetics:*","sns:*","budgets:*","iam:GetRole","iam:GetInstanceProfile","iam:CreateRole","iam:DeleteRole","iam:CreateInstanceProfile","iam:DeleteInstanceProfile","iam:AddRoleToInstanceProfile","iam:RemoveRoleFromInstanceProfile","iam:PutRolePolicy","iam:DeleteRolePolicy","iam:PassRole","iam:TagRole"],Resource:"*"}
    ]
  }' >"${terraform_policy}"
  aws iam put-role-policy --role-name "${terraform_role}" --policy-name OilScopeTerraform \
    --policy-document "file://${terraform_policy}"

  jq -n --arg account "${account}" --arg region "${REGION}" --arg prefix "${DEPLOYMENT}-${ENVIRONMENT}" '{
    Version:"2012-10-17",
    Statement:[
      {Effect:"Allow",Action:["ecr:GetAuthorizationToken"],Resource:"*"},
      {Effect:"Allow",Action:["ecr:BatchCheckLayerAvailability","ecr:CompleteLayerUpload","ecr:GetDownloadUrlForLayer","ecr:InitiateLayerUpload","ecr:PutImage","ecr:UploadLayerPart","ecr:BatchGetImage"],Resource:("arn:aws:ecr:"+$region+":"+$account+":repository/"+$prefix+"-*")}
    ]
  }' >"${ci_policy}"
  aws iam put-role-policy --role-name "${ci_role}" --policy-name OilScopeImagePublisher \
    --policy-document "file://${ci_policy}"

  jq -n --arg account "${account}" --arg region "${REGION}" --arg prefix "${DEPLOYMENT}-${ENVIRONMENT}" '{
    Version:"2012-10-17",
    Statement:[
      {Effect:"Allow",Action:["ecr:GetAuthorizationToken"],Resource:"*"},
      {Effect:"Allow",Action:["ecr:BatchGetImage","ecr:GetDownloadUrlForLayer","ecr:BatchCheckLayerAvailability"],Resource:("arn:aws:ecr:"+$region+":"+$account+":repository/"+$prefix+"-*")},
      {Effect:"Allow",Action:["logs:CreateLogStream","logs:PutLogEvents","cloudwatch:PutMetricData"],Resource:"*"}
    ]
  }' >"${runtime_policy}"
  aws iam put-role-policy --role-name "${runtime_role}" --policy-name OilScopeRuntime \
    --policy-document "file://${runtime_policy}"

  local manifest backend
  manifest="$(jq -n \
    --arg provider aws \
    --arg account_id "${account}" \
    --arg region "${REGION}" \
    --arg state_bucket "${bucket}" \
    --arg state_key "${state_key}" \
    --arg deployment_identity "arn:aws:iam::${account}:role/${terraform_role}" \
    --arg ci_identity "arn:aws:iam::${account}:role/${ci_role}" \
    --arg runtime_identity "arn:aws:iam::${account}:role/${runtime_role}" \
    --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{
      schema_version:1, provider:$provider, account_id:$account_id, region:$region,
      state_bucket:$state_bucket, state_key:$state_key,
      deployment_identity:$deployment_identity, ci_identity:$ci_identity,
      runtime_identity:$runtime_identity, created_at:$created_at
    }')"
  backend="bucket = \"${bucket}\"
key = \"${state_key}\"
region = \"${REGION}\"
encrypt = true
use_lockfile = true"
  write_generated_files_safe "${manifest}" "${backend}"
  rm -R -- "${temp_dir}"
  trap - EXIT

  info "AWS foundation ready. IAM propagation can take several minutes."
  info "Next: aws sts assume-role --role-arn arn:aws:iam::${account}:role/${terraform_role} --role-session-name oilscope-terraform"
  info "Next: terraform -chdir=infrastructure/terraform/stacks/aws init -reconfigure -backend-config=${BACKEND_FILE}"
  info "Next: python3 scripts/validate_project_config.py ${CONFIG}"
  info "Next: terraform -chdir=infrastructure/terraform/stacks/aws plan -var=project_config_path=${CONFIG}"
}

gcp_service_account_exists() {
  gcloud iam service-accounts describe "$1" --project "$2" >/dev/null 2>&1
}

gcp_ensure_service_account() {
  local account_id="$1"
  local display_name="$2"
  local project_id="$3"
  local email="${account_id}@${project_id}.iam.gserviceaccount.com"

  if gcp_service_account_exists "${email}" "${project_id}"; then
    info "GCP service account exists: ${email}"
  else
    action "Creating GCP service account ${email}"
    gcloud iam service-accounts create "${account_id}" \
      --project "${project_id}" \
      --display-name "${display_name}" \
      --quiet
  fi
}

gcp_bind_role() {
  local project_id="$1"
  local member="$2"
  local role="$3"
  gcloud projects add-iam-policy-binding "${project_id}" \
    --member "${member}" \
    --role "${role}" \
    --condition=None \
    --quiet >/dev/null
}

bootstrap_gcp() {
  local project_id project_number active_account bucket state_prefix
  local terraform_id ci_id runtime_id terraform_email ci_email runtime_email
  local github_repository workload_pool workload_provider workload_provider_name
  local missing=0 bucket_exists=false
  local -a services terraform_roles runtime_roles

  project_id="$(jq -r '.clouds.gcp.project_id // empty' "${CONFIG}")"
  [[ -n "${project_id}" ]] || fail "clouds.gcp.project_id is required."
  active_account="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -1)"
  [[ -n "${active_account}" ]] || fail "No active gcloud identity."
  project_number="$(gcloud projects describe "${project_id}" --format='value(projectNumber)' 2>/dev/null)" || \
    fail "GCP project ${project_id} does not exist or the active identity cannot access it. Project creation requires an explicit future opt-in."
  [[ -n "${project_number}" ]] || fail "Unable to resolve the numeric project number for ${project_id}."

  if ! gcloud beta billing projects describe "${project_id}" --format='value(billingEnabled)' 2>/dev/null \
    | grep -qx 'True'; then
    fail "GCP project ${project_id} has no verifiably enabled billing account or billing visibility is missing."
  fi

  bucket="${project_id}-${DEPLOYMENT}-${ENVIRONMENT}-tfstate"
  bucket="${bucket:0:63}"
  state_prefix="${ENVIRONMENT}/${PROVIDER}/${DEPLOYMENT}"
  terraform_id="${DEPLOYMENT}-${ENVIRONMENT}-tf"
  ci_id="${DEPLOYMENT}-${ENVIRONMENT}-ci"
  runtime_id="${DEPLOYMENT}-${ENVIRONMENT}-runtime"
  terraform_id="${terraform_id:0:30}"
  ci_id="${ci_id:0:30}"
  runtime_id="${runtime_id:0:30}"
  terraform_email="${terraform_id}@${project_id}.iam.gserviceaccount.com"
  ci_email="${ci_id}@${project_id}.iam.gserviceaccount.com"
  runtime_email="${runtime_id}@${project_id}.iam.gserviceaccount.com"
  github_repository="$(jq -r '.registry.repository // empty' "${CONFIG}" | sed -E 's#^ghcr.io/([^/]+/[^/]+).*$#\1#')"
  [[ "${github_repository}" == */* ]] || fail "registry.repository must identify a GitHub owner/repository."
  workload_pool="${DEPLOYMENT}-${ENVIRONMENT}-github"
  workload_pool="${workload_pool:0:32}"
  workload_provider="github"
  workload_provider_name="projects/${project_number}/locations/global/workloadIdentityPools/${workload_pool}/providers/${workload_provider}"
  services=(
    cloudresourcemanager.googleapis.com
    serviceusage.googleapis.com
    iam.googleapis.com
    iamcredentials.googleapis.com
    sts.googleapis.com
    compute.googleapis.com
    secretmanager.googleapis.com
    artifactregistry.googleapis.com
    logging.googleapis.com
    monitoring.googleapis.com
    sqladmin.googleapis.com
    servicenetworking.googleapis.com
  )
  terraform_roles=(
    roles/compute.admin
    roles/iam.serviceAccountAdmin
    roles/iam.serviceAccountUser
    roles/secretmanager.admin
    roles/artifactregistry.admin
    roles/logging.configWriter
    roles/monitoring.admin
    roles/cloudsql.admin
    roles/servicenetworking.networksAdmin
    roles/serviceusage.serviceUsageAdmin
  )
  runtime_roles=(
    roles/artifactregistry.reader
    roles/logging.logWriter
    roles/monitoring.metricWriter
  )

  info "GCP target project=${project_id} region=${REGION} account=${active_account}"
  info "State bucket=${bucket} prefix=${state_prefix}"
  if gcloud storage buckets describe "gs://${bucket}" --project "${project_id}" >/dev/null 2>&1; then
    bucket_exists=true
    info "GCP state bucket exists: ${bucket}"
  else
    action "GCP state bucket is missing: ${bucket}"
    ((missing += 1))
  fi
  for email in "${terraform_email}" "${ci_email}" "${runtime_email}"; do
    if gcp_service_account_exists "${email}" "${project_id}"; then
      info "GCP service account exists: ${email}"
    else
      action "GCP service account is missing: ${email}"
      ((missing += 1))
    fi
  done
  if gcloud iam workload-identity-pools describe "${workload_pool}" \
    --location global --project "${project_id}" >/dev/null 2>&1; then
    info "GCP Workload Identity Pool exists: ${workload_pool}"
  else
    action "GCP Workload Identity Pool is missing: ${workload_pool}"
    ((missing += 1))
  fi
  if gcloud iam workload-identity-pools providers describe "${workload_provider}" \
    --workload-identity-pool "${workload_pool}" \
    --location global --project "${project_id}" >/dev/null 2>&1; then
    info "GCP GitHub OIDC provider exists: ${workload_provider_name}"
  else
    action "GCP GitHub OIDC provider is missing: ${workload_provider_name}"
    ((missing += 1))
  fi

  if [[ "${MODE}" == "check" ]]; then
    info "Check complete: ${missing} documented GCP foundation object(s) missing. No changes made."
    return 0
  fi

  info "Mutation authorised by --yes for project=${project_id} region=${REGION}."
  gcloud services enable "${services[@]}" --project "${project_id}" --quiet
  if [[ "${bucket_exists}" == false ]]; then
    gcloud storage buckets create "gs://${bucket}" \
      --project "${project_id}" \
      --location "${REGION}" \
      --uniform-bucket-level-access \
      --public-access-prevention \
      --quiet
  fi
  gcloud storage buckets update "gs://${bucket}" \
    --versioning \
    --uniform-bucket-level-access \
    --public-access-prevention \
    --quiet

  gcp_ensure_service_account "${terraform_id}" "OilScope Terraform deployment" "${project_id}"
  gcp_ensure_service_account "${ci_id}" "OilScope CI image publisher" "${project_id}"
  gcp_ensure_service_account "${runtime_id}" "OilScope runtime foundation" "${project_id}"

  if ! gcloud iam workload-identity-pools describe "${workload_pool}" \
    --location global --project "${project_id}" >/dev/null 2>&1; then
    gcloud iam workload-identity-pools create "${workload_pool}" \
      --location global \
      --project "${project_id}" \
      --display-name "OilScope GitHub Actions" \
      --description "Repository-scoped federation for ${github_repository}" \
      --quiet
  fi
  if ! gcloud iam workload-identity-pools providers describe "${workload_provider}" \
    --workload-identity-pool "${workload_pool}" \
    --location global --project "${project_id}" >/dev/null 2>&1; then
    gcloud iam workload-identity-pools providers create-oidc "${workload_provider}" \
      --workload-identity-pool "${workload_pool}" \
      --location global \
      --project "${project_id}" \
      --display-name "GitHub Actions" \
      --issuer-uri "https://token.actions.githubusercontent.com" \
      --attribute-mapping "google.subject=assertion.sub,attribute.repository=assertion.repository" \
      --attribute-condition "assertion.repository == '${github_repository}'" \
      --quiet
  fi
  gcloud iam workload-identity-pools providers update-oidc "${workload_provider}" \
    --workload-identity-pool "${workload_pool}" \
    --location global \
    --project "${project_id}" \
    --display-name "GitHub Actions" \
    --issuer-uri "https://token.actions.githubusercontent.com" \
    --attribute-mapping "google.subject=assertion.sub,attribute.repository=assertion.repository" \
    --attribute-condition "assertion.repository == '${github_repository}'" \
    --quiet

  local role
  for role in "${terraform_roles[@]}"; do
    gcp_bind_role "${project_id}" "serviceAccount:${terraform_email}" "${role}"
  done
  for role in "${runtime_roles[@]}"; do
    gcp_bind_role "${project_id}" "serviceAccount:${runtime_email}" "${role}"
  done
  gcp_bind_role "${project_id}" "serviceAccount:${ci_email}" "roles/artifactregistry.writer"
  gcloud iam service-accounts add-iam-policy-binding "${ci_email}" \
    --project "${project_id}" \
    --role roles/iam.workloadIdentityUser \
    --member "principalSet://iam.googleapis.com/projects/${project_number}/locations/global/workloadIdentityPools/${workload_pool}/attribute.repository/${github_repository}" \
    --quiet >/dev/null
  gcloud storage buckets add-iam-policy-binding "gs://${bucket}" \
    --member "serviceAccount:${terraform_email}" \
    --role roles/storage.objectAdmin \
    --quiet >/dev/null

  local manifest backend
  manifest="$(jq -n \
    --arg provider gcp \
    --arg project_id "${project_id}" \
    --arg region "${REGION}" \
    --arg state_bucket "${bucket}" \
    --arg state_prefix "${state_prefix}" \
    --arg deployment_identity "${terraform_email}" \
    --arg ci_identity "${ci_email}" \
    --arg ci_oidc_provider "${workload_provider_name}" \
    --arg ci_repository "${github_repository}" \
    --arg runtime_identity "${runtime_email}" \
    --argjson services "$(printf '%s\n' "${services[@]}" | jq -R . | jq -s .)" \
    --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{
      schema_version:1, provider:$provider, project_id:$project_id, region:$region,
      state_bucket:$state_bucket, state_prefix:$state_prefix,
      deployment_identity:$deployment_identity, ci_identity:$ci_identity,
      ci_oidc_provider:$ci_oidc_provider, ci_repository:$ci_repository,
      runtime_identity:$runtime_identity, enabled_services:$services,
      created_at:$created_at
    }')"
  backend="bucket = \"${bucket}\"
prefix = \"${state_prefix}\""
  write_generated_files_safe "${manifest}" "${backend}"

  info "GCP foundation ready. IAM propagation can take several minutes."
  info "Next: gcloud auth application-default login --impersonate-service-account=${terraform_email}"
  info "Next: terraform -chdir=infrastructure/terraform/stacks/gcp init -reconfigure -backend-config=${BACKEND_FILE}"
  info "Next: python3 scripts/validate_project_config.py ${CONFIG}"
  info "Next: terraform -chdir=infrastructure/terraform/stacks/gcp plan -var=project_config_path=${CONFIG}"
}

if [[ "${MODE}" == "check" ]]; then
  info "Running read-only foundation check. Generated files will not be written."
else
  info "State-changing foundation bootstrap requested with --yes."
fi

case "${PROVIDER}" in
  aws) bootstrap_aws ;;
  gcp) bootstrap_gcp ;;
esac
