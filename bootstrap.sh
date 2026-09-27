#!/usr/bin/env bash
set -euo pipefail
umask 077

PROJECT_ID="oil-korzh-tf-bootstrap-260826"
BILLING_ACCOUNT_ID="0128E6-3A4B10-934F5C"
REGION="europe-west1"
SA_NAME="terraform-sa"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
BUCKET_NAME="${PROJECT_ID}-tfstate"
OUTPUT_DIR="${HOME}/.gcp-bootstrap/${PROJECT_ID}"
KEY_FILE="${OUTPUT_DIR}/${SA_NAME}.json"
BACKEND_FILE="${OUTPUT_DIR}/backend.hcl"
ENV_FILE="${OUTPUT_DIR}/terraform.env"

mkdir -p "$OUTPUT_DIR"

if gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
  echo "Project ${PROJECT_ID} already exists; skipping creation"
else
  gcloud projects create "$PROJECT_ID" \
    --name="Terraform training project"
fi

gcloud billing projects link "$PROJECT_ID" \
  --billing-account="$BILLING_ACCOUNT_ID"

gcloud services enable \
  serviceusage.googleapis.com \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com \
  compute.googleapis.com \
  storage.googleapis.com \
  secretmanager.googleapis.com \
  --project="$PROJECT_ID"

if gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Service account ${SA_EMAIL} already exists; skipping creation"
else
  gcloud iam service-accounts create "$SA_NAME" \
    --project="$PROJECT_ID" \
    --display-name="Terraform runner"
fi

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/compute.networkAdmin" \
  --condition=None

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/compute.securityAdmin" \
  --condition=None

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/compute.instanceAdmin.v1" \
  --condition=None

if [[ -s "$KEY_FILE" ]]; then
  echo "Service account key ${KEY_FILE} already exists; skipping creation"
else
  gcloud iam service-accounts keys create "$KEY_FILE" \
    --iam-account="$SA_EMAIL" \
    --project="$PROJECT_ID"
fi

if gcloud storage buckets describe "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
  echo "Bucket gs://${BUCKET_NAME} already exists; skipping creation"
else
  gcloud storage buckets create "gs://${BUCKET_NAME}" \
    --project="$PROJECT_ID" \
    --location="$REGION" \
    --uniform-bucket-level-access \
    --pap
fi

gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/storage.objectAdmin"

cat >"$BACKEND_FILE" <<EOF
bucket = "${BUCKET_NAME}"
prefix = "terraform/state"
EOF

cat >"$ENV_FILE" <<EOF
export GOOGLE_APPLICATION_CREDENTIALS="${KEY_FILE}"
export GOOGLE_CLOUD_PROJECT="${PROJECT_ID}"
export TF_VAR_project_id="${PROJECT_ID}"
export TF_VAR_region="${REGION}"
export TF_BACKEND_CONFIG="${BACKEND_FILE}"
EOF

chmod 600 "$KEY_FILE" "$BACKEND_FILE" "$ENV_FILE"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../infrastructure/terraform"

export GOOGLE_APPLICATION_CREDENTIALS="$KEY_FILE"
export GOOGLE_CLOUD_PROJECT="$PROJECT_ID"

terraform -chdir="$TERRAFORM_DIR" init \
  -reconfigure \
  -backend-config="$BACKEND_FILE"

echo "Terraform GCS backend initialized with ${BACKEND_FILE}"
