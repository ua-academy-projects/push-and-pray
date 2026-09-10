# host_baseline

Prepares Ubuntu workload VMs with the common operating-system state required
before Docker and application roles run. The role installs prerequisite
packages, creates the locked deployment account, manages OilScope directories
and permissions, and configures the provider-native host metrics and system log
agent selected by the inventory's `oilscope_cloud` variable.

## Requirements

- Ansible Core 2.21 or newer.
- An Ubuntu managed host with Python available.
- An SSH user permitted to use privilege escalation.

## Variables

- `host_baseline_deploy_user`: deployment system user; defaults to `deploy`.
- `host_baseline_deploy_group`: deployment system group; defaults to `deploy`.
- `host_baseline_packages`: packages installed on every workload VM.
- `host_baseline_directories`: directories with their owner, group, and mode.
- `host_baseline_cloudwatch_agent_url`: regional Amazon CloudWatch Agent package.
- `host_baseline_ops_agent_install_script_url`: official Google Cloud Ops Agent
  repository installer.

See `defaults/main.yml` for the complete default values.

## Dependencies

The production inventory must define `oilscope_cloud`; AWS hosts also use its
`oilscope_region` variable. Docker, Compose, runtime secrets, and application
services are managed by separate collection roles.

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
