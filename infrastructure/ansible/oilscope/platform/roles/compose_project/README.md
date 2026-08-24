# Compose project

Installs the supported OilScope Compose definition and its non-secret deployment
configuration.

## Requirements

The target must have the `deploy` user and group created by the VM bootstrap.
The controller must have access to the external project configuration JSON.

## Role variables

- `compose_project_config_path`: required controller-side path to the non-secret
  project configuration JSON.
- `compose_project_workload`: required key in the JSON `workloads` object.
- `compose_project_dir`: installation directory; defaults to `/opt/oilscope/app`.
- `compose_project_owner` and `compose_project_group`: installed file ownership;
  both default to `deploy`.

The selected workload's `image_tag` must be a full 40-character Git SHA. The
role writes it as `APP_IMAGE_TAG` in `deployment.env`. Secret values are not
handled by this role.

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
        compose_project_workload: history
```

The installed files are `/opt/oilscope/app/compose.yaml` and
`/opt/oilscope/app/deployment.env` by default.

## License

GPL-2.0-or-later
