# Tailscale-managed multi-cloud K3s

Terraform owns the tagged pre-authentication key and, when explicitly enabled,
the entire tailnet policy. The policy grants `tag:subnet-router` permission to
advertise the three configured VPC/VNet routes and permits routed traffic among
those CIDRs. Ansible installs the client and performs `tailscale up` inside the
bastion VMs; Terraform cannot execute that host-local command safely.

## Enablement

1. Use a new tailnet, or import its existing policy before Terraform manages
   it: `terraform import tailscale_acl.multicloud[0] acl`.
2. In the private project config, set `tailscale.enabled` to `true`. Set
   `manage_policy` to `true` only after importing/reviewing the existing policy;
   `tailscale_acl` replaces the whole policy file.
3. Export either the OAuth client credentials or an API key. OAuth is preferred:
   `TAILSCALE_OAUTH_CLIENT_ID`, `TAILSCALE_OAUTH_CLIENT_SECRET`, and optionally
   `TAILSCALE_TAILNET=-`.
4. Apply Terraform, then expose the sensitive output only to the Ansible
   process: `export OILSCOPE_TAILSCALE_AUTH_KEY="$(terraform output -raw tailscale_subnet_router_auth_key)"`.
5. Run `ansible-playbook oilscope.platform.deploy_multicloud_k3s`.

The auth key is sensitive but necessarily resides in Terraform state. Protect
the GCS backend with encryption, least-privilege IAM, and no state downloads to
untrusted machines.
