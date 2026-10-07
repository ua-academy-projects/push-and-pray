# Tailscale subnet-router role

Installs Tailscale from its official stable Ubuntu repository and configures
the bastion as an IPv4 subnet router. The advertised route is derived from
`network.vpc_cidr`, and the MagicDNS device name is derived from the project
name, environment, and `bastion` suffix. This keeps routing configuration in
one place.

The first run reads a reusable, ephemeral, tagged auth key from the controller's
`TAILSCALE_AUTH_KEY` environment variable. Reusability lets the key enroll a
replacement bastion after a Terraform rebuild, while ephemerality removes stale
bastion identities from the tailnet. Ansible writes the key to a temporary
root-only file, authenticates with Tailscale's `file:` auth-key mechanism, and
removes the file in an `always` block. Later runs on the same VM use the
persisted Tailscale node identity and do not require the environment variable.

Create the key with `tag:oilscope-bastion`, and make it pre-approved when
tailnet device approval is enabled. Store it outside the repository and project
configuration, give it a short practical expiry, and revoke it when it is no
longer required.

The role enables IPv4 forwarding, explicitly keeps subnet-route SNAT enabled,
disables acceptance of tailnet DNS on the bastion, and reconciles the
advertised VPC route. Route approval and tailnet access grants remain explicit
administrator actions outside the VM.

Invoke the role through its playbook:

```bash
ansible-playbook oilscope.platform.configure_tailscale_subnet_router \
  -i infrastructure/ansible/inventory/oilscope.yml
```
