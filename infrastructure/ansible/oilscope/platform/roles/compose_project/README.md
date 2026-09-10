# Compose project

Installs one selected OilScope Compose definition. Each workload VM receives
only its own application services:

- `database`: PostgreSQL and the one-shot migration service;
- `history`: History only;
- `fetcher`: Fetcher only;
- `ui`: UI only.

The UI VM also receives the separate `proxy` definition for Traefik.

## Requirements

The target must have the `deploy` user and group created by the
`oilscope.platform.host_baseline` role.
The controller must have access to the external project configuration JSON.

## Role variables

- `compose_project_config_path`: required controller-side path to the non-secret
  project configuration JSON.
- `compose_project_workload`: required workload name: `database`, `history`,
  `fetcher`, `ui`, or `proxy`.
- `compose_project_dir`: installation directory; defaults to `/opt/oilscope/app`.
- `compose_project_owner` and `compose_project_group`: installed file ownership;
  both default to `deploy`.

Image references are rendered from `registry.repository` and
`registry.image_tag` in the project configuration. Secret values and private
registry authentication are not handled by this role.

## Example playbook

```yaml
---
- name: Install Compose project
  hosts: history
  become: true
  roles:
    - role: oilscope.platform.compose_project
      vars:
        compose_project_config_path: /srv/oilscope/project-config.json
        compose_project_workload: history
```

The installed file is `/opt/oilscope/app/compose.yaml`.

`compose.deployment.yaml.j2` is retained only with the historical workload
cloud-init implementation. The current Ansible role does not select or install
it.

## License

GPL-2.0-or-later
