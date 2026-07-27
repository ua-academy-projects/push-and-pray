#!/usr/bin/env bash
set -euo pipefail

readonly PRIVATE_ADDRESS="192.168.100.13"
readonly HISTORY_ADDRESS="192.168.100.11"
readonly DATABASE_NAME="aegis_history"
readonly DATABASE_USER="aegis_history"
readonly PASSWORD_FILE="/tmp/aegis-mariadb-password"
readonly MARIADB_CONFIG="/etc/mysql/mariadb.conf.d/60-aegis.cnf"

fail() {
  echo "Aegis MariaDB provisioning failed: $*" >&2
  exit 1
}

[[ -f "${PASSWORD_FILE}" ]] || \
  fail "missing MariaDB password upload; check AEGIS_DATABASE_SECRET_FILE"
trap 'rm -f "${PASSWORD_FILE}"' EXIT

DATABASE_PASSWORD="$(<"${PASSWORD_FILE}")"
[[ -n "${DATABASE_PASSWORD}" ]] || fail "database password must not be empty"
[[ "${DATABASE_PASSWORD}" != *$'\n'* ]] || \
  fail "database password file must contain exactly one line"
[[ "${DATABASE_PASSWORD}" =~ ^[A-Za-z0-9._~!@%^+=:-]+$ ]] || \
  fail "database password contains unsupported characters"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install --yes --no-install-recommends mariadb-server

install -d -o root -g root -m 0755 /etc/mysql/mariadb.conf.d
temporary_config="$(mktemp)"
trap 'rm -f "${temporary_config}" "${PASSWORD_FILE}"' EXIT
cat >"${temporary_config}" <<EOF
[mariadb]
bind-address = ${PRIVATE_ADDRESS}
skip-name-resolve
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
EOF
install -o root -g root -m 0644 "${temporary_config}" "${MARIADB_CONFIG}"

systemctl enable mariadb
systemctl restart mariadb

mysqladmin --protocol=socket ping >/dev/null || fail "MariaDB socket health check failed"

# Quote the one externally supplied SQL string without exposing it in tracked
# files or command-line arguments.
sql_password="${DATABASE_PASSWORD//\\/\\\\}"
sql_password="${sql_password//\'/\'\'}"

mariadb --protocol=socket <<SQL
CREATE DATABASE IF NOT EXISTS \`${DATABASE_NAME}\`
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DATABASE_USER}'@'${HISTORY_ADDRESS}';
ALTER USER '${DATABASE_USER}'@'${HISTORY_ADDRESS}'
  IDENTIFIED BY '${sql_password}';
REVOKE ALL PRIVILEGES, GRANT OPTION
  FROM '${DATABASE_USER}'@'${HISTORY_ADDRESS}';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, DROP, INDEX, REFERENCES
  ON \`${DATABASE_NAME}\`.*
  TO '${DATABASE_USER}'@'${HISTORY_ADDRESS}';
DELETE FROM mysql.global_priv WHERE User = '';
DELETE FROM mysql.global_priv
WHERE User = 'root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
FLUSH PRIVILEGES;
SQL

mariadb --protocol=socket --batch --skip-column-names <<SQL | grep -Fxq "${DATABASE_NAME}" || \
  fail "database verification failed"
SELECT SCHEMA_NAME
FROM INFORMATION_SCHEMA.SCHEMATA
WHERE SCHEMA_NAME = '${DATABASE_NAME}'
  AND DEFAULT_CHARACTER_SET_NAME = 'utf8mb4';
SQL

mariadb --protocol=socket --batch --skip-column-names <<SQL | grep -Fxq "${DATABASE_USER}@${HISTORY_ADDRESS}" || \
  fail "restricted database account verification failed"
SELECT CONCAT(User, '@', Host)
FROM mysql.user
WHERE User = '${DATABASE_USER}' AND Host = '${HISTORY_ADDRESS}';
SQL

expected_grants=(
  ALTER
  CREATE
  DELETE
  DROP
  INDEX
  INSERT
  REFERENCES
  SELECT
  UPDATE
)
for privilege in "${expected_grants[@]}"; do
  mariadb --protocol=socket --batch --skip-column-names <<SQL | \
    grep -Fxq "${privilege}" || fail "missing ${privilege} grant for History"
SELECT PRIVILEGE_TYPE
FROM INFORMATION_SCHEMA.SCHEMA_PRIVILEGES
WHERE GRANTEE = CONCAT(QUOTE('${DATABASE_USER}'), '@', QUOTE('${HISTORY_ADDRESS}'))
  AND TABLE_SCHEMA = '${DATABASE_NAME}'
  AND PRIVILEGE_TYPE = '${privilege}';
SQL
done

echo "MariaDB is healthy on ${PRIVATE_ADDRESS}:3306"
echo "Verified ${DATABASE_NAME} and ${DATABASE_USER}@${HISTORY_ADDRESS}"
