# Technitium private DNS role

Runs a pinned Technitium DNS Server container on the bastion and reconciles
authoritative zones for the private web services in `project-config.json`.
DNS and the administration interface bind only to the bastion's private VPC
address. No public firewall rule is created.

The administrator password is read from the controller's
`TECHNITIUM_ADMIN_PASSWORD` environment variable and stored in a root-only file
because Docker needs it when recreating the container. Technitium consumes the
password during first initialization; changing the environment variable does
not rotate an existing installation's password.

Run the public playbook from the repository root:

```bash
export TECHNITIUM_ADMIN_PASSWORD="$(cat)"
# Paste the password, then press Ctrl+D.

ansible-playbook oilscope.platform.configure_private_dns \
  -i infrastructure/ansible/inventory/oilscope.yml

unset TECHNITIUM_ADMIN_PASSWORD
```

Configure the bastion private address as a restricted nameserver in the
Tailscale DNS administration page for each private hostname. The role denies
recursive queries; it answers only the authoritative zones it manages. Its
container also has a continuous health check against Technitium's DNS-client
health endpoint.

The Headlamp, Homepage, and Technitium console records resolve to the private
K3s ingress agents in self-managed mode, or to the managed cluster's reserved
internal ingress address in managed mode. The console itself continues running
on the bastion; the `k3s_technitium_proxy` role forwards its private HTTPS
Ingress to the bastion administration port. The direct bastion URL remains a
recovery fallback.
