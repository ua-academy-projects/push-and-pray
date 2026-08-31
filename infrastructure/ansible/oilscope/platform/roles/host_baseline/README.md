# host_baseline

Prepares Ubuntu workload VMs with the common operating-system state required
before Docker and application roles run. The role installs prerequisite
packages, creates the locked deployment account, and manages OilScope
directories and permissions.

## Requirements

- Ansible Core 2.21 or newer.
- An Ubuntu managed host with Python available.
- An SSH user permitted to use privilege escalation.

## Variables

- `host_baseline_deploy_user`: deployment system user; defaults to `deploy`.
- `host_baseline_deploy_group`: deployment system group; defaults to `deploy`.
- `host_baseline_packages`: packages installed on every workload VM.
- `host_baseline_directories`: directories with their owner, group, and mode.

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
