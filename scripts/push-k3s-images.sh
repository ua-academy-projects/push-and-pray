#!/usr/bin/env bash
set -euo pipefail

: "${OILSCOPE_IMAGE_TAG:?Export OILSCOPE_IMAGE_TAG before building and deploying}"
registry_json="$(terraform -chdir=infrastructure/terraform output -json container_registry)"
cloud="$(jq -r '.cloud' <<<"$registry_json")"
server="$(jq -r '.server' <<<"$registry_json")"
region="$(jq -r '.region' <<<"$registry_json")"
name="$(jq -r '.name' <<<"$registry_json")"
tag="$OILSCOPE_IMAGE_TAG"

case "$cloud" in
  azure)
    az acr login --name "$name"
    ;;
  aws)
    aws ecr get-login-password --region "$region" | docker login --username AWS --password-stdin "$server"
    ;;
  gcp)
    gcloud auth configure-docker "$server" --quiet
    ;;
  *)
    echo "Unsupported container registry cloud: $cloud" >&2
    exit 1
    ;;
esac

images=(history fetcher ui)
if [[ "$(terraform -chdir=infrastructure/terraform output -raw database_mode)" == postgres_extensions ]]; then
  images+=(database-cnpg)
fi

for image in "${images[@]}"; do
  repository="$(jq -r --arg image "$image" '.images[$image]' <<<"$registry_json")"
  image_tag="$tag"
  if [[ "$image" == database-cnpg ]]; then
    # CNPG requires the PostgreSQL major version at the beginning of the tag.
    image_tag="18-$tag"
  fi
  if [[ -z "$repository" || "$repository" == null ]]; then
    echo "Missing registry repository for $image; apply the registry Terraform changes first." >&2
    exit 1
  fi
  docker buildx build --platform linux/amd64 --push \
    --file "infrastructure/docker/Dockerfile.$image" \
    --tag "$repository:$image_tag" .
done
