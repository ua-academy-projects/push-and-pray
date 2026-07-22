#!/usr/bin/env bash

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

readonly APP_ROOT="/opt/weather-app"


log() {
    printf '\n[weather-app] %s\n' "$*"
}


install_packages() {
    apt-get install -y --no-install-recommends "$@"
}


install_python_runtime() {
    log "Installing the shared Python runtime"

    install_packages \
        python3 \
        python3-venv \
        rsync
}


install_python_requirements() {
    local virtualenv_dir="$1"
    local requirements_file="$2"

    "${virtualenv_dir}/bin/pip" install \
        --disable-pip-version-check \
        --upgrade pip

    "${virtualenv_dir}/bin/pip" install \
        --disable-pip-version-check \
        -r "${requirements_file}"
}


sync_python_service() {
    local service_name="$1"
    local source_dir="/vagrant/${service_name}/"
    local target_dir="${APP_ROOT}/${service_name}"
    local virtualenv_dir="${target_dir}/venv"
    local import_check="from flask import Flask; import requests"

    if [[ "${service_name}" == "backend-service" ]]; then
        import_check="from flask import Flask; import requests, psycopg, apscheduler"
    fi

    log "Synchronizing ${service_name}"

    install -d \
        -o vagrant \
        -g vagrant \
        "${target_dir}"

    rsync -a --delete \
        --exclude '.env' \
        --exclude '.venv' \
        --exclude 'venv' \
        --exclude '__pycache__' \
        "${source_dir}" \
        "${target_dir}/"

    if [[ ! -x "${virtualenv_dir}/bin/python" ]]; then
        log "Creating the ${service_name} virtual environment"
        python3 -m venv "${virtualenv_dir}"
    fi

    install_python_requirements \
        "${virtualenv_dir}" \
        "${target_dir}/requirements.txt"

    if ! "${virtualenv_dir}/bin/python" \
        -c "${import_check}"; then

        log "Repairing the ${service_name} virtual environment"
        rm -rf "${virtualenv_dir}"
        python3 -m venv "${virtualenv_dir}"

        install_python_requirements \
            "${virtualenv_dir}" \
            "${target_dir}/requirements.txt"
    fi

    chown -R \
        vagrant:vagrant \
        "${target_dir}"
}


enable_and_restart_service() {
    local service_name="$1"

    log "Enabling ${service_name}"

    systemctl daemon-reload
    systemctl enable "${service_name}"
    systemctl restart "${service_name}"
}


configure_common_system() {
    log "Updating package metadata"
    apt-get update

    log "Installing common system packages"
    install_packages \
        ca-certificates \
        curl

    install -d "${APP_ROOT}"
}


if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    configure_common_system
    log "Common provisioning completed"
fi
