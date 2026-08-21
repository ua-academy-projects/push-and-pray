#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PUBLISH_SCRIPT="${ROOT_DIR}/infrastructure/terraform/scripts/publish-secrets.sh"
RUNTIME_SECRET_WRAPPER="${ROOT_DIR}/infrastructure/terraform/scripts/load-runtime-secrets.sh"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "${TEST_DIR}"' EXIT

bash -n "${PUBLISH_SCRIPT}" "${RUNTIME_SECRET_WRAPPER}"

fake_bin="${TEST_DIR}/bin"
mkdir -p "${fake_bin}"
cat > "${fake_bin}/gcloud" <<'FAKE_GCLOUD'
#!/usr/bin/env bash
set -Eeuo pipefail
count_file="${TEST_CAPTURE_DIR}/count"
count=0
if [[ -f "${count_file}" ]]; then
  count="$(<"${count_file}")"
fi
count=$((count + 1))
printf '%s' "${count}" > "${count_file}"
printf '%s\n' "$*" >> "${TEST_CAPTURE_DIR}/args"
cat > "${TEST_CAPTURE_DIR}/payload-${count}"
FAKE_GCLOUD
chmod +x "${fake_bin}/gcloud"

if TEST_CAPTURE_DIR="${TEST_DIR}" PATH="${fake_bin}:${PATH}" env -i \
  PATH="${fake_bin}:${PATH}" HOME="${HOME:-}" bash "${PUBLISH_SCRIPT}" \
  >"${TEST_DIR}/missing.stdout" 2>"${TEST_DIR}/missing.stderr"; then
  printf 'Missing secrets unexpectedly passed validation.\n' >&2
  exit 1
fi
if [[ -e "${TEST_DIR}/count" ]]; then
  printf 'gcloud was invoked before missing-secret validation completed.\n' >&2
  exit 1
fi

fake_secret='known-fake-secret-value'
TEST_CAPTURE_DIR="${TEST_DIR}" PATH="${fake_bin}:${PATH}" \
  DB_PASSWORD="${fake_secret}" \
  OILPRICEAPI_KEY="another-fake-secret" \
  DB_PASSWORD_SECRET_ID='db-password' \
  OILPRICEAPI_KEY_SECRET_ID='oilpriceapi-key' \
  bash "${PUBLISH_SCRIPT}" >"${TEST_DIR}/success.stdout" 2>"${TEST_DIR}/success.stderr"

if grep -R -q --fixed-strings "${fake_secret}" "${TEST_DIR}/success.stdout" "${TEST_DIR}/success.stderr" "${TEST_DIR}/args"; then
  printf 'A secret value was exposed in command output or arguments.\n' >&2
  exit 1
fi
if [[ "$(<"${TEST_DIR}/payload-1")" != "${fake_secret}" ]]; then
  printf 'DB_PASSWORD was not sent through gcloud stdin.\n' >&2
  exit 1
fi
if [[ "$(<"${TEST_DIR}/payload-2")" != 'another-fake-secret' ]]; then
  printf 'OILPRICEAPI_KEY was not sent through gcloud stdin.\n' >&2
  exit 1
fi
if grep -R -q -- '--data-file=-' "${TEST_DIR}/args" && grep -R -q --fixed-strings "${fake_secret}" "${TEST_DIR}/args"; then
  printf 'Secret payload appeared in gcloud arguments.\n' >&2
  exit 1
fi
if find "${TEST_DIR}" -type f \( -name '*.env' -o -name '*.tfvars' -o -name '*.tfstate*' \) | grep -q .; then
  printf 'A persistent secret configuration file was created during publishing.\n' >&2
  exit 1
fi

if ! grep -q -- '--data-file=-' "${PUBLISH_SCRIPT}"; then
  printf 'Secret publishing must use stdin and never CLI payload arguments.\n' >&2
  exit 1
fi
if grep -Eq 'env_file:|\.env' "${ROOT_DIR}"/infrastructure/docker/compose.*.yaml; then
  printf 'Compose files must not load an implicit or explicit env file.\n' >&2
  exit 1
fi
if ! grep -q -- 'export.*environment_name' "${RUNTIME_SECRET_WRAPPER}"; then
  printf 'Runtime wrapper must provide retrieved secrets through process environment.\n' >&2
  exit 1
fi
if ! grep -q -- 'export COMPOSE_DISABLE_ENV_FILE=1' "${RUNTIME_SECRET_WRAPPER}"; then
  printf 'Runtime wrapper must disable Docker Compose implicit .env loading.\n' >&2
  exit 1
fi
if ! grep -q 'secretmanager.googleapis.com' "${RUNTIME_SECRET_WRAPPER}"; then
  printf 'Runtime deployment must retrieve secrets from Secret Manager.\n' >&2
  exit 1
fi
if ! grep -q -- '/run/oil-price-tracker-secrets' "${RUNTIME_SECRET_WRAPPER}"; then
  printf 'Runtime wrapper must keep temporary Docker configuration under /run.\n' >&2
  exit 1
fi
if grep -qE '(/etc|/opt|/tmp)/[^ ]*\.env' "${RUNTIME_SECRET_WRAPPER}"; then
  printf 'Runtime deployment must not create persistent env files.\n' >&2
  exit 1
fi

printf 'Deployment contract checks passed.\n'
