# Docker Engine

Installs Docker Engine and the Compose plugin from Docker's official stable
Ubuntu repository, enables the service, and grants the configured local
accounts access to the Docker socket.

## Requirements

- Ubuntu with outbound access to `download.docker.com`.
- Gathered Ansible facts.
- Privilege escalation on the target host.

The `host_baseline` role normally runs first and creates the `deploy` account.

## Variables

- `docker_engine_packages`: packages installed from Docker's repository.
- `docker_engine_conflicting_packages`: distribution packages removed before
  Docker Engine is installed.
- `docker_engine_keyring_path`, `docker_engine_gpg_url`,
  `docker_engine_repository_url`, `docker_engine_repository_component`, and
  `docker_engine_repository_path`: repository configuration.
- `docker_engine_service`, `docker_engine_service_enabled`, and
  `docker_engine_service_state`: Docker service configuration.
- `docker_engine_group` and `docker_engine_group_members`: Docker group and
  existing local accounts added to it.

## Usage

```yaml
---
- name: Install Docker Engine
  hosts: vms
  become: true
  roles:
    - docker_engine
```
