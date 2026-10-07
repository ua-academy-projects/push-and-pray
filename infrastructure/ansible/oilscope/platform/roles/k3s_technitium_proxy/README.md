# K3s Technitium proxy role

Runs on the local Ansible controller and publishes the bastion-hosted
Technitium administration console through private K3s ingress. The role creates
a selectorless ClusterIP Service whose Ansible-managed EndpointSlice points to
the bastion's private address. Technitium itself remains outside Kubernetes, so
private DNS continues working when the cluster is unavailable.

Traefik terminates the DNS-01 certificate for
`k3s.private_services.technitium.hostname`, permanently redirects HTTP to
HTTPS, and accepts only traffic forwarded by the Tailscale subnet router. The
GCP firewall separately permits K3s nodes to reach only the configured
Technitium administration port on the bastion.

Deploy the proxy through the controller-side add-on playbook after Terraform
has applied the firewall rule and the private DNS playbook has reconciled the
hostname:

```bash
ansible-playbook oilscope.platform.deploy_k3s_addons \
  -i localhost, \
  -e k3s_addons_config_file="$PWD/project-config.json"
```

The direct bastion URL remains available as a recovery path from a tailnet
client if K3s ingress is unavailable.
