# Bastion

Configures key-only SSH access to the bastion and allows TCP forwarding for
connections to private VMs through `ProxyJump`.

## Requirements

- Ubuntu with OpenSSH Server.
- Privilege escalation on the target host.

## Variables

- `bastion_ssh_port`: required SSH port for the bastion.
- `bastion_sshd_drop_in_path`: managed SSH drop-in location.

## Usage

```yaml
---
- name: Configure the bastion
  hosts: bastion
  become: true
  roles:
    - role: bastion
```

Terraform must allow the configured port before this role runs. When changing
the port from 22, the calling playbook must reset its SSH connection and use
the new port after the role completes.
