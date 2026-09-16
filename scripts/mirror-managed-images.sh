#!/usr/bin/env bash

set -Eeuo pipefail

CONFIG="${1:?project config path is required}"
IMAGES_FILE="${2:?managed service images JSON path is required}"

for command_name in jq docker; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    printf 'ERROR: Required command not found: %s\n' "${command_name}" >&2
    exit 1
  }
done

docker buildx version >/dev/null

REGISTRY_DOCKER_CONFIG="$(mktemp -d)"
export DOCKER_CONFIG="${REGISTRY_DOCKER_CONFIG}"
trap 'rm -rf "${REGISTRY_DOCKER_CONFIG}"' EXIT

while IFS= read -r cloud; do
  registry="$(jq -r --arg cloud "${cloud}" '.[$cloud].registry' "${IMAGES_FILE}")"

  case "${cloud}" in
    aws)
      command -v aws >/dev/null 2>&1 || {
        printf 'ERROR: Required command not found: aws\n' >&2
        exit 1
      }
      region="$(jq -r '.clouds.aws.locations[.defaults.location_profile].region' "${CONFIG}")"
      aws ecr get-login-password --region "${region}" |
        docker login --username AWS --password-stdin "${registry}" >/dev/null
      ;;
    gcp)
      command -v gcloud >/dev/null 2>&1 || {
        printf 'ERROR: Required command not found: gcloud\n' >&2
        exit 1
      }
      gcloud auth print-access-token |
        docker login --username oauth2accesstoken --password-stdin "${registry}" >/dev/null
      ;;
    *)
      printf 'ERROR: Unsupported registry cloud: %s\n' "${cloud}" >&2
      exit 1
      ;;
  esac

  for service in redis rabbitmq; do
    source_image="$(jq -r --arg service "${service}" '.managed_services[$service].source_image' "${CONFIG}")"
    target_image="$(jq -r --arg cloud "${cloud}" --arg service "${service}" '.[$cloud][$service]' "${IMAGES_FILE}")"
    printf 'Mirroring %s to %s\n' "${source_image}" "${target_image}"
    docker buildx imagetools create --tag "${target_image}" "${source_image}"
  done
done < <(jq -r 'to_entries[] | select(.value != null) | .key' "${IMAGES_FILE}")
