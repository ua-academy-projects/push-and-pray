#!/usr/bin/env bash
set -euo pipefail

mariadb_user_host="${MARIADB_USER_HOST:-192.168.100.11}"

mariadb --protocol=socket --user=root \
  --password="${MARIADB_ROOT_PASSWORD}" <<SQL
DROP USER IF EXISTS '${MARIADB_USER}'@'%';
CREATE USER IF NOT EXISTS '${MARIADB_USER}'@'${mariadb_user_host}'
  IDENTIFIED BY '${MARIADB_PASSWORD}';
ALTER USER '${MARIADB_USER}'@'${mariadb_user_host}'
  IDENTIFIED BY '${MARIADB_PASSWORD}';
REVOKE ALL PRIVILEGES, GRANT OPTION
  FROM '${MARIADB_USER}'@'${mariadb_user_host}';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, DROP, INDEX, REFERENCES
  ON \`${MARIADB_DATABASE}\`.*
  TO '${MARIADB_USER}'@'${mariadb_user_host}';
FLUSH PRIVILEGES;
SQL
