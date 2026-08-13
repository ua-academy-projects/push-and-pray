#!/bin/sh

set -eu

case "${APP_DOMAIN:-}" in
  ""|.*|*..*|*.|*[!A-Za-z0-9.-]*)
    echo "APP_DOMAIN must be a valid DNS name" >&2
    exit 1
    ;;
esac

: "${CERTBOT_EMAIL:?CERTBOT_EMAIL is required}"

certificate="/etc/letsencrypt/live/${APP_DOMAIN}/fullchain.pem"
webroot="/var/www/certbot"

trap 'exit 0' INT TERM

if [ ! -s "${certificate}" ]; then
  until certbot certonly \
    --webroot \
    --webroot-path "${webroot}" \
    --domain "${APP_DOMAIN}" \
    --cert-name "${APP_DOMAIN}" \
    --email "${CERTBOT_EMAIL}" \
    --agree-tos \
    --no-eff-email \
    --non-interactive \
    --keep-until-expiring; do
    echo "Certificate request failed; retrying in 15 minutes" >&2
    sleep 900 &
    wait $!
  done
fi

while :; do
  certbot renew \
    --webroot \
    --webroot-path "${webroot}" \
    --quiet || true
  sleep 43200 &
  wait $!
done
