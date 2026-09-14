# host_baseline

Prepares Ubuntu workload VMs with the common operating-system state required
before Docker and application roles run. The role installs prerequisite
packages, creates the locked deployment account, manages OilScope
directories and permissions, and sizes the journal for container output.

## Requirements

- Ansible Core 2.21 or newer.
- An Ubuntu managed host with Python available.
- An SSH user permitted to use privilege escalation.

## Variables

- `host_baseline_deploy_user`: deployment system user; defaults to `deploy`.
- `host_baseline_deploy_group`: deployment system group; defaults to `deploy`.
- `host_baseline_packages`: packages installed on every workload VM.
- `host_baseline_packages_by_cloud`: extra packages one provider's hosts need,
  keyed by cloud. AWS hosts get the AWS CLI, which `resolve_secrets` uses to
  read secrets with the instance role; GCP hosts need nothing extra.
- `host_baseline_cloud`: which cloud this host is on. Defaults to
  `oilscope_cloud` from the dynamic inventory; an unknown value simply adds no
  extra packages.
- `host_baseline_directories`: directories with their owner, group, and mode.
- `host_baseline_journald_config_path` and `host_baseline_journald_config`:
  journal settings written as a drop-in. The defaults keep the journal on
  disk, cap it at 500 MB, and raise the per-unit rate limit: every container
  logs through `docker.service`, so the limit that suits a single daemon
  would silently drop a chatty container's lines.

See `defaults/main.yml` for the complete default values.

## Dependencies

None. Docker, Compose, runtime secrets, and application services are managed by
separate collection roles.

## Usage

```yaml
---
- name: Prepare OilScope workload hosts
  hosts: workloads
  become: true
  roles:
    - oilscope.platform.host_baseline
```

The production inventory is supplied separately. For an isolated role test,
provide an external inventory containing a `host_baseline_test` group.
