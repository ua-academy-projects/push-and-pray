#!/usr/bin/env bash

set -Eeuo pipefail

CONFIG="${1:?project config path is required}"
REGISTRY_FILE="${2:?Terraform registry output JSON path is required}"

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

for command_name in jq docker; do
  command -v "${command_name}" >/dev/null 2>&1 || fail "Required command not found: ${command_name}"
done
docker buildx version >/dev/null || fail "Docker Buildx is required."
jq empty "${CONFIG}" "${REGISTRY_FILE}"

PROVIDER="$(jq -r '.provider // empty' "${REGISTRY_FILE}")"
REGISTRY="$(jq -r '.host // empty' "${REGISTRY_FILE}")"
[[ -n "${REGISTRY}" ]] || fail "Terraform registry output has no host."

REGISTRY_DOCKER_CONFIG="$(mktemp -d)"
export DOCKER_CONFIG="${REGISTRY_DOCKER_CONFIG}"
trap 'rm -R -- "${REGISTRY_DOCKER_CONFIG}"' EXIT

case "${PROVIDER}" in
  aws)
    command -v aws >/dev/null 2>&1 || fail "Required command not found: aws"
    REGION="$(jq -r '.clouds.aws.locations[.defaults.location_profile].region' "${CONFIG}")"
    aws ecr get-login-password --region "${REGION}" |
      docker login --username AWS --password-stdin "${REGISTRY}" >/dev/null
    ;;
  gcp)
    command -v gcloud >/dev/null 2>&1 || fail "Required command not found: gcloud"
    gcloud auth print-access-token |
      docker login --username oauth2accesstoken --password-stdin "${REGISTRY}" >/dev/null
    ;;
  *) fail "Unsupported registry provider: ${PROVIDER:-<missing>}" ;;
esac

manifest_digest() {
  docker buildx imagetools inspect "$1" --format '{{json .Manifest}}' 2>/dev/null |
    jq -er '.digest'
}

promote_image() {
  local source_image="$1"
  local target_image="$2"
  local source_digest target_digest

  [[ "${source_image}" == *@sha256:* || "${source_image}" =~ :[0-9a-f]{40}$ ]] || \
    fail "Source image is not immutable: ${source_image}"
  source_digest="$(manifest_digest "${source_image}")" || \
    fail "Cannot resolve source image digest: ${source_image}"
  if target_digest="$(manifest_digest "${target_image}")"; then
    [[ "${target_digest}" == "${source_digest}" ]] || \
      fail "Immutable target ${target_image} exists with a different digest."
    printf 'Already promoted: %s (%s)\n' "${target_image}" "${target_digest}"
    return
  fi

  printf 'Promoting %s -> %s\n' "${source_image}" "${target_image}"
  docker buildx imagetools create --tag "${target_image}" "${source_image}"
  target_digest="$(manifest_digest "${target_image}")" || \
    fail "Cannot resolve promoted target digest: ${target_image}"
  [[ "${target_digest}" == "${source_digest}" ]] || \
    fail "Digest mismatch after promotion: source=${source_digest} target=${target_digest}"
}

SOURCE_REPOSITORY="$(jq -r '.registry.repository' "${CONFIG}")"
SOURCE_SHA="$(jq -r '.registry.image_sha' "${CONFIG}")"
for service in fetcher history ui database; do
  target_image="$(jq -r --arg service "${service}" '.application[$service] // empty' "${REGISTRY_FILE}")"
  [[ -n "${target_image}" ]] || fail "Missing target image for ${service}."
  promote_image "${SOURCE_REPOSITORY}/${service}:${SOURCE_SHA}" "${target_image}"
done

while IFS= read -r service; do
  source_image="$(jq -r --arg service "${service}" '.managed_services[$service].source_image' "${CONFIG}")"
  target_image="$(jq -r --arg service "${service}" '.managed[$service]' "${REGISTRY_FILE}")"
  promote_image "${source_image}" "${target_image}"
done < <(jq -r '.managed | keys[]' "${REGISTRY_FILE}")
