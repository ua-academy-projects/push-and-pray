#!/bin/bash
# Runs once, only against a freshly-initialized (empty) data volume -- the
# official postgres image already creates $POSTGRES_DB for us; this adds the
# second database backend-service's test suite uses (see
# backend-service/pytest.ini), owned by the same app role.
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE DATABASE "${POSTGRES_TEST_DB}" OWNER "${POSTGRES_USER}";
EOSQL
