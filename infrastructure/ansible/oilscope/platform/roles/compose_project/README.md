# Compose project

Installs the Compose definition for one OilScope workload VM. Each target gets
only the services assigned to its role:

- `database`: PostgreSQL and the one-shot migration service;
- `history`: History only;
- `fetcher`: Fetcher only;
- `ui`: UI only.

## Requirements

The target must have the `deploy` user and group created by the VM bootstrap.
The controller must have access to the external project configuration JSON.

## Role variables

- `compose_project_config_path`: required controller-side path to the non-secret
  project configuration JSON.
- `compose_project_workload`: required host role: `database`, `history`,
  `fetcher`, or `ui`.
- `compose_project_dir`: installation directory; defaults to `/opt/oilscope/app`.
- `compose_project_owner` and `compose_project_group`: installed file ownership;
  both default to `deploy`.

Image references are rendered from `registry.repository` and
`registry.image_sha` in the project configuration. Secret values and private
registry authentication are not handled by this role.

## Example playbook

```yaml
---
- name: Install Compose project
  hosts: workloads
  become: true
  roles:
    - role: oilscope.platform.compose_project
      vars:
        compose_project_config_path: /srv/oilscope/project-config.json
        compose_project_workload: "{{ oilscope_role }}"
```

The installed file is `/opt/oilscope/app/compose.yaml`.

`compose.deployment.yaml.j2` remains temporarily as input to the legacy
Terraform cloud-init path. The Ansible role does not install it.

## Test

From the collection directory, render and validate all four definitions with:

```sh
ansible-playbook \
  -i roles/compose_project/tests/inventory \
  roles/compose_project/tests/test.yml \
  -e project_config_path=/absolute/path/to/project-config.json
```

## License

GPL-2.0-or-later
