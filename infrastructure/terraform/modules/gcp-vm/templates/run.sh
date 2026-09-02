#!/bin/sh
set -eu

: "${AUTOMATION_ROLE:?AUTOMATION_ROLE is required}"

case "$AUTOMATION_ROLE" in
    database|history|fetcher|ui) ;;
    none)
        echo "AUTOMATION_ROLE is none - nothing to deploy on this VM" >&2
        exit 0
        ;;
    *)
        echo "unknown AUTOMATION_ROLE: $AUTOMATION_ROLE" >&2
        exit 1
        ;;
esac

case "$AUTOMATION_ROLE" in
  database) compose_services="postgres migrate" ;;
  *)        compose_services="$AUTOMATION_ROLE" ;;
esac

: "${GHCR_USERNAME:?GHCR_USERNAME is required}"
: "${GHCR_TOKEN:?GHCR_TOKEN is required}"
echo "$GHCR_TOKEN" | docker login ghcr.io --username "$GHCR_USERNAME" --password-stdin
docker compose -f compose.deployment.yaml pull $compose_services

case "$AUTOMATION_ROLE" in
  database) ;;
  *)
    : "${DATABASE_HOST:?DATABASE_HOST is required}"
    : "${DATABASE_PORT:=5432}"
    : "${POSTGRES_IMAGE:?POSTGRES_IMAGE is required}"

    attempt=1
    max_attempts=30

    until docker run --rm "$POSTGRES_IMAGE" pg_isready --host="$DATABASE_HOST" --port="$DATABASE_PORT"
    do
      if [ "$attempt" -ge "$max_attempts" ]; then
        echo "PostgreSQL at $DATABASE_HOST:$DATABASE_PORT did not become ready" >&2
        exit 1
      fi
      attempt=$((attempt + 1))
      sleep 2
    done
    ;;
esac

case "$AUTOMATION_ROLE" in
  database)
    docker compose -f compose.deployment.yaml up -d postgres
    docker compose -f compose.deployment.yaml run --rm migrate
    ;;
  *)
    docker compose -f compose.deployment.yaml up -d --no-deps "$AUTOMATION_ROLE"
    ;;
esac


case "$AUTOMATION_ROLE" in
  database) ;;
  history) health_url="http://127.0.0.1:${HISTORY_HOST_PORT:-8001}/health"; health_expected='"pgmq_consumer":"ready"' ;;
  fetcher) health_url="http://127.0.0.1:${FETCHER_HOST_PORT:-8002}/health"; health_expected='"delivery":"pgmq"' ;;
  ui)      health_url="http://127.0.0.1:${UI_HTTP_PORT:-80}/health";       health_expected='"sessions":"postgresql"' ;;
esac

case "$AUTOMATION_ROLE" in
  database) ;;
  *)
    attempt=1
    max_attempts=30

    until response="$(curl --fail --silent --show-error --max-time 5 "$health_url")"; do
      if [ "$attempt" -ge "$max_attempts" ]; then
        echo "$AUTOMATION_ROLE did not become healthy at $health_url" >&2
        exit 1
      fi
      attempt=$((attempt + 1))
      sleep 2
    done

    if ! printf '%s' "$response" | grep --fixed-strings --quiet "$health_expected"; then
      echo "$AUTOMATION_ROLE health response missing $health_expected: $response" >&2
      exit 1
    fi
    ;;
esac
