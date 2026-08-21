#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PUBLISH_SCRIPT="${ROOT_DIR}/infrastructure/terraform/scripts/publish-secrets.sh"
CLOUD_INIT_TEMPLATE="${ROOT_DIR}/infrastructure/terraform/modules/vm/cloud-init.yaml.tftpl"

bash -n "${PUBLISH_SCRIPT}"

fake_bin="$(mktemp -d)"
trap 'rm -rf "${fake_bin}"' EXIT
cat > "${fake_bin}/gcloud" <<'FAKE_GCLOUD'
#!/usr/bin/env bash
printf 'gcloud must not be called when validation fails\n' >&2
exit 99
FAKE_GCLOUD
chmod +x "${fake_bin}/gcloud"

if PATH="${fake_bin}:${PATH}" bash "${PUBLISH_SCRIPT}" >/tmp/oil-tracker-test-output 2>&1; then
  printf 'Missing secrets unexpectedly passed validation.\n' >&2
  exit 1
fi
if grep -q 'gcloud must not be called' /tmp/oil-tracker-test-output; then
  printf 'Secret validation ran too late.\n' >&2
  exit 1
fi
rm -f /tmp/oil-tracker-test-output

if grep -Eq -- '--data-file=-[^[:space:]]|gcloud secrets versions add[^|]*\$\{(DB_PASSWORD|OILPRICEAPI_KEY)' "${PUBLISH_SCRIPT}"; then
  printf 'Secret publishing must use stdin and never CLI payload arguments.\n' >&2
  exit 1
fi
if grep -Eq 'env_file:|\.env' "${ROOT_DIR}"/infrastructure/docker/compose.*.yaml; then
  printf 'Compose files must not load an implicit or explicit env file.\n' >&2
  exit 1
fi
if ! grep -q -- '--env-file /dev/stdin' "${CLOUD_INIT_TEMPLATE}"; then
  printf 'Runtime deployment must provide Compose variables through stdin.\n' >&2
  exit 1
fi
if ! grep -q 'secretmanager.googleapis.com' "${CLOUD_INIT_TEMPLATE}"; then
  printf 'Runtime deployment must retrieve secrets from Secret Manager.\n' >&2
  exit 1
fi
if grep -qE '(/etc|/opt|/tmp)/[^ ]*\.env' "${CLOUD_INIT_TEMPLATE}"; then
  printf 'Runtime deployment must not create persistent env files.\n' >&2
  exit 1
fi

printf 'Deployment contract checks passed.\n'
