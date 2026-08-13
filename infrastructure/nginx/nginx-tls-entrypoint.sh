#!/bin/sh

set -eu

case "${APP_DOMAIN:-}" in
  ""|.*|*..*|*.|*[!A-Za-z0-9.-]*)
    echo "APP_DOMAIN must be a valid DNS name" >&2
    exit 1
    ;;
esac

certificate="/etc/letsencrypt/live/${APP_DOMAIN}/fullchain.pem"
private_key="/etc/letsencrypt/live/${APP_DOMAIN}/privkey.pem"
config_path="/etc/nginx/conf.d/default.conf"

certificate_state() {
  if [ -s "${certificate}" ] && [ -s "${private_key}" ]; then
    printf 'tls:%s:%s\n' \
      "$(readlink "${certificate}" 2>/dev/null || printf present)" \
      "$(readlink "${private_key}" 2>/dev/null || printf present)"
  else
    printf 'http\n'
  fi
}

render_config() {
  state="$(certificate_state)"
  if [ "${state}" = "http" ]; then
    template="/etc/nginx/templates/petroscope/http.conf.template"
    echo "Starting Nginx in HTTP bootstrap mode for ${APP_DOMAIN}"
  else
    template="/etc/nginx/templates/petroscope/https.conf.template"
    echo "Configuring HTTPS for ${APP_DOMAIN}"
  fi

  envsubst '${APP_DOMAIN}' < "${template}" > "${config_path}.new"
  mv "${config_path}.new" "${config_path}"
  printf '%s\n' "${state}"
}

current_state="$(render_config | tail -n 1)"
nginx -t

watch_certificates() {
  while sleep 30; do
    next_state="$(certificate_state)"
    if [ "${next_state}" != "${current_state}" ]; then
      current_state="$(render_config | tail -n 1)"
      if nginx -t; then
        nginx -s reload
      fi
    fi
  done
}

watch_certificates &
exec "$@"
