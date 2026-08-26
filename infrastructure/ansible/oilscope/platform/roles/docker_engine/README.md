# Docker Engine

Installs a pinned Docker Engine with the Compose plugin from Docker's official
apt repository, holds the pinned packages, and enables the service.

This role reproduces the Docker portion of the Terraform cloud-init bootstrap
in `infrastructure/terraform/modules/vm/templates/cloud-config.yaml.tftpl` so
that bootstrap can eventually be removed.

## Requirements

The target must be a Debian-family host with outbound access to
`download.docker.com`. Privilege escalation is required; the role requests it
per task.

Prerequisite packages (`ca-certificates`, `curl`, `jq`), the `deploy` account
and the OilScope directories belong to `host_baseline` and are not installed
here. The role fetches the signing key with `ansible.builtin.get_url` rather
than `curl`, so it does not depend on `host_baseline` having run first —
though the deployment playbook applies the baseline first regardless.

## Role variables

- `docker_engine_version`: exact apt version for the pinned packages; defaults
  to `5:29.7.2-1~ubuntu.26.04~resolute`. Re-verify with
  `apt-cache madison docker-ce` before bumping.
- `docker_engine_pinned_packages`: packages installed at that exact version;
  defaults to `docker-ce` and `docker-ce-cli`.
- `docker_engine_packages`: packages installed unversioned; defaults to
  `containerd.io`, `docker-buildx-plugin` and `docker-compose-plugin`.
- `docker_engine_hold` and `docker_engine_held_packages`: whether to mark
  packages `hold`, and which ones. Enabled by default.
- `docker_engine_validate_release`: refuse to run when the pinned version was
  built for a different Ubuntu release. Enabled by default.
- `docker_engine_keyring_path`, `docker_engine_gpg_url`,
  `docker_engine_repository_url`, `docker_engine_repository_component`,
  `docker_engine_repository_path`: signing key and repository locations.
- `docker_engine_service`, `docker_engine_service_enabled`,
  `docker_engine_service_state`: systemd service management.
- `docker_engine_group` and `docker_engine_group_members`: accounts granted
  access to the Docker socket. Members that do not exist on the target are
  skipped rather than created.

The repository is written in deb822 format to
`/etc/apt/sources.list.d/docker.sources`. The apt cache is refreshed only when
that file changes, which keeps a repeat run free of changes.

## Dependencies

None declared. The deployment playbook applies `host_baseline` before this
role.

## Example playbook

```yaml
---
- name: Install Docker Engine
  hosts: workloads
  roles:
    - role: oilscope.platform.docker_engine
```

## License

GPL-2.0-or-later
