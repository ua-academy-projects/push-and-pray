# Cloudflare DNS and K3s HTTPS

The aggregate K3s deployment serves the UI through Traefik Ingress. Terraform
points the proxied Cloudflare A record at the one K3s node with a public IP and
sets Cloudflare SSL to `strict`. Ansible installs cert-manager with the official
Helm chart. cert-manager uses Let's Encrypt and Cloudflare DNS-01 to issue and
renew the `oilscope-ui-tls` Kubernetes Secret; the UI Ingress consumes that Secret.

```text
Browser -> Cloudflare -> public K3s node :443 -> Traefik -> UI Service
                         cert-manager -> Let's Encrypt DNS-01 -> Cloudflare
```

Set `cloudflare.enabled`, `zone_id`, `hostname`, `proxied: true`, and
`acme_email` in the shared project configuration. Exactly one non-bastion K3s
node must set `assign_public_ip: true`. The public node is only an ingress
address; Kubernetes may schedule UI, History, and Fetcher pods on any node.
Terraform opens ports 80 and 443 on that node when Cloudflare is enabled.

Create a Cloudflare API token scoped to the zone with DNS Edit, Zone Read, and
Zone Settings Edit permissions. Export `CLOUDFLARE_API_TOKEN` for Terraform and
the Ansible control machine. Store the value outside Git. Terraform uses it to
manage DNS and the strict SSL setting. Ansible writes it to a Kubernetes Secret
in the `oilscope` namespace, referenced by the cert-manager Issuer. The token
is never included in project configuration.

From the repository root, after providing cloud credentials and applying a
reviewed Terraform plan, run the aggregate deployment:

```sh
export CLOUDFLARE_API_TOKEN=...       # provide the scoped token locally
export OILSCOPE_IMAGE_TAG=...         # published immutable image tag
ansible-playbook -i infrastructure/ansible/inventory/oilscope.yml \
  infrastructure/ansible/oilscope/platform/playbooks/deploy_workloads.yml \
  -e project_config_path="$PWD/project-config.json"
```

The control host needs `kubectl`, Helm, the `kubernetes.core` Ansible collection,
and access to the cloud secret service and container registry. Ansible uses the
inventory's bastion SSH route to tunnel to the first server's K3s API; the
kubeconfig is kept in a private temporary directory and removed at the end.

A one-time domain registrar change may still be needed to delegate the zone to
Cloudflare. No certificate copying or renewal hook participates in the K3s
path. The standalone Compose `ui.yml` playbook is a legacy deployment path with
its own Nginx/Certbot behavior and is not part of the aggregate K3s workflow.
