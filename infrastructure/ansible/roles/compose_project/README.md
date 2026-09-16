# Compose project

Renders the Docker Compose definition needed by one OilScope VM. The role
uses the shared `oilscope_config` variable loaded by `inventory/group_vars/all.yml`.

Supported values of `compose_project_workload` are:

- `database`;
- `history`;
- `fetcher`;
- `ui`;
- `proxy`.

## Requirements

- The `deploy` user and group created by `host_baseline`.
- `oilscope_config` containing the validated project configuration.

## Variables

- `compose_project_workload`: required workload or proxy name.
- `compose_project_dir`: installation directory; defaults to
  `/opt/oilscope/app`.
- `compose_project_owner` and `compose_project_group`: installed file
  ownership; both default to `deploy`.

## Usage

```yaml
---
- name: Install the Compose project
  hosts: vms
  become: true
  roles:
    - role: compose_project
      vars:
        compose_project_workload: "{{ oilscope_role }}"
```

The resulting file is `{{ compose_project_dir }}/compose.yaml`.
