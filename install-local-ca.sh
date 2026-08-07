#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERTIFICATE_PATH="${1:-${PROJECT_ROOT}/tls/wildlife-local-root-ca.crt}"
CERTIFICATE_NAME="wildlife-local-root-ca.crt"

if [ ! -s "$CERTIFICATE_PATH" ]; then
    echo "CA certificate was not found: ${CERTIFICATE_PATH}" >&2
    echo "Start/provision the UI machine first, then run this script again." >&2
    exit 1
fi

run_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        echo "Root access is required, but sudo is not installed." >&2
        echo "Run this script as root." >&2
        exit 1
    fi
}

if command -v openssl >/dev/null 2>&1; then
    echo "Installing this local CA:"
    openssl x509 \
        -in "$CERTIFICATE_PATH" \
        -noout \
        -subject \
        -fingerprint \
        -enddate
fi

if command -v update-ca-certificates >/dev/null 2>&1; then
    # Debian, Ubuntu and derivatives.
    destination="/usr/local/share/ca-certificates/${CERTIFICATE_NAME}"
    run_as_root install -m 0644 "$CERTIFICATE_PATH" "$destination"
    run_as_root update-ca-certificates
elif command -v update-ca-trust >/dev/null 2>&1; then
    # Fedora, RHEL, CentOS and derivatives.
    destination="/etc/pki/ca-trust/source/anchors/${CERTIFICATE_NAME}"
    run_as_root install -m 0644 "$CERTIFICATE_PATH" "$destination"
    run_as_root update-ca-trust extract
else
    echo "Unsupported Linux CA store." >&2
    echo "Expected update-ca-certificates or update-ca-trust." >&2
    exit 1
fi

echo "The local CA is now trusted by the Linux system."
echo "Restart the browser, then open the application over HTTPS."
