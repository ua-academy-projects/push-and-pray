#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${PROJECT_ROOT}/deploy.env"
LOCAL_SSH_DIRECTORY="${HOME}/.ssh"
LOCAL_SSH_CONFIG="${LOCAL_SSH_DIRECTORY}/config"
BLOCK_START="# BEGIN ANIMAL-POPULATION-UKRAINE VMS"
BLOCK_END="# END ANIMAL-POPULATION-UKRAINE VMS"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Create deploy.env from deploy.env.example first." >&2
    exit 1
fi

set -a
# shellcheck disable=SC1090
source "$CONFIG_FILE"
set +a

VM_ADMIN_USER="${VM_ADMIN_USER:-wildlife}"
roles=(logging database redis fetcher backend ui)
host_variables=(LOGGING_HOST DB_HOST REDIS_HOST FETCHER_HOST BACKEND_HOST UI_HOST)

mkdir -p "$LOCAL_SSH_DIRECTORY"
chmod 0700 "$LOCAL_SSH_DIRECTORY" 2>/dev/null || true
touch "$LOCAL_SSH_CONFIG"

generated_config="$(mktemp)"
updated_config="$(mktemp)"
trap 'rm -f "$generated_config" "$updated_config"' EXIT

for index in "${!roles[@]}"; do
    role="${roles[$index]}"
    host_variable="${host_variables[$index]}"
    host_address="${!host_variable}"

    vagrant_config="$(vagrant ssh-config "$role")"
    identity_file="$(
        printf '%s\n' "$vagrant_config" \
            | awk '
                $1 == "IdentityFile" {
                    sub(/^[[:space:]]*IdentityFile[[:space:]]+/, "")
                    gsub(/^"|"$/, "")
                    print
                    exit
                }
            '
    )"

    if [ -z "$identity_file" ] || [ ! -f "$identity_file" ]; then
        echo "SSH private key for ${role} was not found." >&2
        exit 1
    fi

    if command -v cygpath >/dev/null 2>&1; then
        identity_file="$(cygpath -m "$identity_file")"
    fi

    {
        printf 'Host %s wildlife-%s\n' "$role" "$role"
        printf '    HostName %s\n' "$host_address"
        printf '    User %s\n' "$VM_ADMIN_USER"
        printf '    Port 22\n'
        printf '    IdentityFile "%s"\n' "$identity_file"
        printf '    IdentitiesOnly yes\n'
        printf '    StrictHostKeyChecking accept-new\n'
        printf '    ConnectTimeout 10\n'
        printf '    ServerAliveInterval 30\n'
        printf '    ServerAliveCountMax 3\n\n'
    } >> "$generated_config"
done

awk \
    -v block_start="$BLOCK_START" \
    -v block_end="$BLOCK_END" '
        $0 == block_start { inside_block = 1; next }
        $0 == block_end { inside_block = 0; next }
        !inside_block { print }
    ' "$LOCAL_SSH_CONFIG" > "$updated_config"

{
    printf '\n%s\n' "$BLOCK_START"
    cat "$generated_config"
    printf '%s\n' "$BLOCK_END"
} >> "$updated_config"

cp "$updated_config" "$LOCAL_SSH_CONFIG"
chmod 0600 "$LOCAL_SSH_CONFIG" 2>/dev/null || true

echo "SSH aliases were added to ${LOCAL_SSH_CONFIG}:"
printf '  ssh %s\n' "${roles[@]}"
