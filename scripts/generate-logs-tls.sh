#!/usr/bin/env bash
set -euo pipefail

logs_ip="${1:?logs IP is required}"
output_dir="${2:?output directory is required}"
stamp="rates-logs:${logs_ip}:v1"

command -v openssl >/dev/null 2>&1 || { echo "openssl is required" >&2; exit 1; }
if [[ -f "${output_dir}/stamp" && -f "${output_dir}/ca.crt" && \
      -f "${output_dir}/server.crt" && -f "${output_dir}/server.key" && \
      "$(<"${output_dir}/stamp")" == "${stamp}" ]] && \
   openssl x509 -checkend 2592000 -noout -in "${output_dir}/server.crt" >/dev/null 2>&1; then
  exit 0
fi

temporary_dir="$(mktemp -d)"
trap 'rm -rf "${temporary_dir}"' EXIT
umask 077

openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 3650 \
  -keyout "${temporary_dir}/ca.key" \
  -out "${temporary_dir}/ca.crt" \
  -subj "/CN=Rateboard local logging CA" >/dev/null 2>&1

{
  echo '[req]'
  echo 'distinguished_name = dn'
  echo 'req_extensions = extensions'
  echo 'prompt = no'
  echo '[dn]'
  echo 'CN = rates-logs'
  echo '[extensions]'
  echo 'subjectAltName = @alt_names'
  echo '[alt_names]'
  echo 'DNS.1 = rates-logs'
  printf 'IP.1 = %s\n' "${logs_ip}"
} > "${temporary_dir}/server.conf"

openssl req -newkey rsa:3072 -sha256 -nodes \
  -keyout "${temporary_dir}/server.key" \
  -out "${temporary_dir}/server.csr" \
  -config "${temporary_dir}/server.conf" >/dev/null 2>&1
openssl x509 -req -sha256 -days 825 \
  -in "${temporary_dir}/server.csr" \
  -CA "${temporary_dir}/ca.crt" \
  -CAkey "${temporary_dir}/ca.key" \
  -CAcreateserial \
  -out "${temporary_dir}/server.crt" \
  -extensions extensions \
  -extfile "${temporary_dir}/server.conf" >/dev/null 2>&1

install -d -m 0700 "${output_dir}"
install -m 0600 "${temporary_dir}/ca.key" "${output_dir}/ca.key"
install -m 0644 "${temporary_dir}/ca.crt" "${output_dir}/ca.crt"
install -m 0600 "${temporary_dir}/server.key" "${output_dir}/server.key"
install -m 0644 "${temporary_dir}/server.crt" "${output_dir}/server.crt"
printf '%s\n' "${stamp}" > "${output_dir}/stamp"
chmod 0600 "${output_dir}/stamp"
