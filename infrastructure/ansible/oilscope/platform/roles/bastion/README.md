# Bastion

Configures SSH access to the bastion. The port comes from
`vms.bastion.ssh_port` in the project config.

## Requirements

- Ubuntu with OpenSSH Server.
- Privilege escalation on the target host.

## Variables

- `bastion_ssh_port`: SSH port; defaults to `ansible_port`.
- `bastion_sshd_drop_in_path`: managed SSH drop-in location.

## Usage

```yaml
---
- name: Configure the bastion
  hosts: bastion
  become: true
  roles:
    - role: oilscope.platform.bastion
```

Terraform enables the configured port before this role runs.
