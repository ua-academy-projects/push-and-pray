# Bastion

Configures the OilScope bastion SSH daemon with the port declared at
`vms.bastion.ssh_port` in the non-secret project configuration JSON. The role
keeps public-key authentication and TCP forwarding enabled while disabling
password, keyboard-interactive and root login.

The role manages only
`/etc/ssh/sshd_config.d/00-oilscope-bastion.conf`. It validates the complete
daemon configuration with `sshd -t` before restarting SSH. On Ubuntu systems
where `ssh.socket` is active, the handler reloads systemd and restarts the
socket so its listener follows the configured port; otherwise it restarts
`ssh.service`.

## Requirements

- Ansible Core 2.16 or newer.
- An Ubuntu host with Python and OpenSSH Server available.
- An SSH user permitted to use privilege escalation.
- Controller access to both the current and configured SSH ports while the
  role changes the listener.

## Variables

- `bastion_project_config_path`: controller-side path to project config JSON;
  defaults to the shared `project_config_path` extra variable.
- `bastion_sshd_drop_in_dir` and `bastion_sshd_drop_in_path`: managed SSH
  drop-in locations.
- `bastion_ssh_connect_timeout`, `bastion_ssh_connect_retries` and
  `bastion_ssh_connect_delay`: controller-side reachability check settings.

## Usage

```yaml
---
- name: Configure the bastion
  hosts: bastion
  become: true
  roles:
    - role: oilscope.platform.bastion
```

Run the collection bootstrap playbook for a fresh VM so Ansible connects to
the image's initial SSH port before this role activates the configured port.
