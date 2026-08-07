#!/usr/bin/env bash
set -uo pipefail

CONFIG_FILE="${WILDLIFE_LOG_CONFIG:-/etc/wildlife-log-collector.conf}"

if [ ! -r "$CONFIG_FILE" ]; then
    echo "Log collector config is not readable: ${CONFIG_FILE}" >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

required_values=(
    LOG_DIRECTORY
    STATE_DIRECTORY
    TARGETS_FILE
    SSH_USER
    SSH_KEY_PATH
    SSH_KNOWN_HOSTS_PATH
)
for variable_name in "${required_values[@]}"; do
    if [ -z "${!variable_name:-}" ]; then
        echo "Missing collector setting: ${variable_name}" >&2
        exit 1
    fi
done

umask 0027
install -d -m 0750 "$LOG_DIRECTORY" "$STATE_DIRECTORY"
touch "$SSH_KNOWN_HOSTS_PATH"
chmod 0600 "$SSH_KNOWN_HOSTS_PATH"

exec 9>"${STATE_DIRECTORY}/collector.lock"
if ! flock -n 9; then
    echo "A previous log collection is still running." >&2
    exit 0
fi

ERROR_LOG="${LOG_DIRECTORY}/collector-errors.log"
failures=0

record_error() {
    printf '%s %s\n' "$(date --iso-8601=seconds)" "$*" >> "$ERROR_LOG"
}

append_result() {
    local role="$1"
    local temporary_file="$2"
    local cursor_file="${STATE_DIRECTORY}/${role}.cursor"
    local next_cursor=""
    local cursor_temporary=""

    next_cursor="$(
        sed -n 's/^-- cursor: //p' "$temporary_file" | tail -n 1
    )"
    sed '/^-- cursor: /d' "$temporary_file" \
        >> "${LOG_DIRECTORY}/${role}.log"

    if [ -n "$next_cursor" ]; then
        cursor_temporary="${cursor_file}.tmp"
        printf '%s\n' "$next_cursor" > "$cursor_temporary"
        mv -f "$cursor_temporary" "$cursor_file"
    fi
}

collect_local() {
    local role="logging"
    local temporary_file=""
    local cursor_file="${STATE_DIRECTORY}/${role}.cursor"
    local journal_arguments=()

    temporary_file="$(mktemp "${STATE_DIRECTORY}/${role}.XXXXXX")"
    if [ -s "$cursor_file" ]; then
        journal_arguments=(--after-cursor "$(<"$cursor_file")")
    else
        journal_arguments=(--boot)
    fi

    if journalctl \
        --no-pager \
        --quiet \
        --output=short-iso-precise \
        --show-cursor \
        "${journal_arguments[@]}" \
        > "$temporary_file"; then
        append_result "$role" "$temporary_file"
    else
        record_error "Failed to collect the local journal."
        failures=$((failures + 1))
    fi

    rm -f "$temporary_file"
}

collect_remote() {
    local role="$1"
    local host="$2"
    local temporary_file=""
    local cursor_file="${STATE_DIRECTORY}/${role}.cursor"
    local cursor=""
    local remote_command=""

    if ! [[ "$role" =~ ^[a-z][a-z0-9_-]*$ ]]; then
        record_error "Skipped invalid role from targets file: ${role}"
        failures=$((failures + 1))
        return
    fi
    if ! [[ "$host" =~ ^[0-9a-fA-F:.]+$ ]]; then
        record_error "Skipped invalid host for ${role}: ${host}"
        failures=$((failures + 1))
        return
    fi

    temporary_file="$(mktemp "${STATE_DIRECTORY}/${role}.XXXXXX")"
    if [ -s "$cursor_file" ]; then
        cursor="$(<"$cursor_file")"
        printf -v remote_command \
        'journalctl --no-pager --quiet --output=short-iso-precise --show-cursor --after-cursor=%q' \
            "$cursor"
    else
        remote_command="journalctl --no-pager --quiet "
        remote_command+="--output=short-iso-precise --show-cursor "
        remote_command+="--boot"
    fi

    if ssh \
        -n \
        -i "$SSH_KEY_PATH" \
        -o BatchMode=yes \
        -o ConnectTimeout=10 \
        -o StrictHostKeyChecking=accept-new \
        -o "UserKnownHostsFile=${SSH_KNOWN_HOSTS_PATH}" \
        "${SSH_USER}@${host}" \
        "$remote_command" \
        > "$temporary_file"; then
        append_result "$role" "$temporary_file"
    else
        record_error "Failed to collect ${role} journal from ${host}."
        failures=$((failures + 1))
    fi

    rm -f "$temporary_file"
}

collect_local

while read -r role host extra; do
    if [ -z "${role:-}" ] || [[ "$role" == \#* ]]; then
        continue
    fi
    if [ -z "${host:-}" ] || [ -n "${extra:-}" ]; then
        record_error "Skipped malformed targets line for ${role}."
        failures=$((failures + 1))
        continue
    fi
    collect_remote "$role" "$host"
done < "$TARGETS_FILE"

exit "$failures"
