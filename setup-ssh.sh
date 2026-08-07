#!/usr/bin/env bash
set -euo pipefail

machines=(db backend fetcher ui)
ssh_user="weather"
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ssh_dir="${HOME}/.ssh"
key_dir="${ssh_dir}/weather-vagrant"
generated_config="${ssh_dir}/weather-vagrant.conf"
main_config="${ssh_dir}/config"
begin_marker="# BEGIN weather-vagrant (managed by setup-ssh.sh)"
end_marker="# END weather-vagrant (managed by setup-ssh.sh)"

if command -v vagrant.exe >/dev/null 2>&1; then
    vagrant_command=(vagrant.exe)
elif command -v vagrant >/dev/null 2>&1; then
    vagrant_command=(vagrant)
else
    echo "Vagrant was not found. Install it or add vagrant.exe to WSL PATH." >&2
    exit 1
fi

mkdir -p "${ssh_dir}" "${key_dir}"
chmod 700 "${ssh_dir}" "${key_dir}"

temp_config="$(mktemp)"
temp_main="$(mktemp)"
trap 'rm -f "${temp_config}" "${temp_main}"' EXIT
cd "${project_dir}"

for machine in "${machines[@]}"; do
    raw_config="$("${vagrant_command[@]}" ssh-config "${machine}" | tr -d '\r')"

    host_name="$(
        "${vagrant_command[@]}" ssh "${machine}" \
            -c "sed -n 's/^LAN_IP=//p' /etc/weatherflow/lan.env" |
        tr -d '\r' |
        tail -n 1
    )"
    port="22"
    source_key="$(sed -n 's/^[[:space:]]*IdentityFile[[:space:]]\+//p' <<<"${raw_config}" | head -n 1)"
    source_key="${source_key%\"}"
    source_key="${source_key#\"}"

    if [[ "${source_key}" =~ ^[A-Za-z]:/ ]]; then
        source_key="$(wslpath -u "${source_key}")"
    fi
    if [[ -z "${host_name}" || -z "${port}" || ! -f "${source_key}" ]]; then
        echo "Could not obtain complete SSH settings for '${machine}'." >&2
        exit 1
    fi

    local_key="${key_dir}/${machine}_private_key"
    cp "${source_key}" "${local_key}"
    chmod 600 "${local_key}"
    cat >>"${temp_config}" <<EOF
Host ${machine}
  HostName ${host_name}
  User ${ssh_user}
  Port ${port}
  IdentityFile ${local_key}
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

EOF
done

install -m 600 "${temp_config}" "${generated_config}"
touch "${main_config}"
chmod 600 "${main_config}"
awk -v begin="${begin_marker}" -v end="${end_marker}" '
    $0 == begin { managed = 1; next }
    $0 == end { managed = 0; next }
    !managed { print }
' "${main_config}" >"${temp_main}"
cat >>"${temp_main}" <<EOF

${begin_marker}
Include ${generated_config}
${end_marker}
EOF
install -m 600 "${temp_main}" "${main_config}"

echo "Native WSL SSH aliases are ready:"
printf '  ssh %s\n' "${machines[@]}"
