# Tailscale networking for K3s

The `deploy_k3s` playbook installs Tailscale on every discovered `k3s_server`
and `k3s_agent` before preparing or installing K3s. Each node joins the same
tailnet under its deterministic inventory name, such as
`<name_prefix>-<environment>-<vm-key>`. Bastions remain the SSH jump hosts for
first contact with private nodes; they do not join Tailscale or route subnets.
The Ansible controller also does not need to join the tailnet.

For a new cluster, K3s uses each node's Tailscale IPv4 as `node-ip` and, on
servers, as `advertise-address`. Joining servers and agents use the primary
server's Tailscale IPv4 on port 6443; Flannel uses `tailscale0`. Tailscale must
be connected before the K3s play runs.

An existing K3s cluster with embedded etcd keeps its original provider-private
node and peer addresses. Etcd member peer addresses cannot be changed safely by
rewriting K3s configuration during a rolling restart: peers still connect to
the old address, while the restarted member's certificate contains the new one.
The playbook detects existing servers without the Tailnet initialization marker
and preserves private transport for the whole cluster. Tailscale still joins
each node, but moving an established etcd cluster onto it requires a separate,
backed-up member migration. A fresh Tailnet cluster records its transport choice
before K3s initializes, so an interrupted deployment keeps the same addresses
when it resumes.

The role installs the stable Ubuntu Tailscale package through its signed apt
repository, starts `tailscaled`, and checks connection state. It retrieves an
auth key only when disconnected. The key is read on the Ansible controller from
the existing GCP Secret Manager, AWS Secrets Manager, or Azure Key Vault flow
for that node's cloud and region. The physical secret name is
`<name_prefix>-<environment>-tailscale-auth-key`. The key is transferred to a
root-only temporary file in `/run`, passed to `tailscale up` by file path, and
removed after the join. It is never sent to Terraform or inventory. On a
connected node, a repeat run reads the address without authenticating again.

Use a **reusable, non-ephemeral** Tailscale auth key for these long-lived VMs.
If device approval is enabled, make it pre-authorized. A tagged key with a
tailnet policy that permits K3s node-to-node traffic is recommended. Provision
the same key into every cloud secret scope used by the K3s nodes. If the key
expires, connected nodes normally keep working, but replacement nodes need a
new stored key. Restrict access to the provider secret and rotate it through
the same upload flow.

## Deployment

Start with provisioned VMs, working bastion SSH, and the controller's existing
cloud CLI credentials. The private nodes need outbound internet through their
existing cloud NAT to reach Tailscale and the apt repository. The current
firewall rules already allow outbound traffic; no new public inbound rule or
Tailscale listening port is required. Direct peer connectivity may depend on
provider NAT behavior, so Tailscale may use relays. Tailnet access rules must
permit K3s API, etcd, kubelet, and Flannel traffic between these nodes.

From the repository root, install the updated collection, then upload the auth
key to the existing provider secret stores. Set the key in the controller
environment without placing it in shell history or a tracked file:

```sh
cd infrastructure/ansible/oilscope/platform
ansible-galaxy collection build --force
ansible-galaxy collection install oilscope-platform-*.tar.gz --force
cd ../../../..
export OILSCOPE_PROJECT_CONFIG=/absolute/path/project-config.json
read -r -s TAILSCALE_AUTH_KEY
export TAILSCALE_AUTH_KEY
ansible-playbook oilscope.platform.upload_secret_versions \
  -e project_config_path="$OILSCOPE_PROJECT_CONFIG" \
  -e '{"secret_versions_only":["TAILSCALE_AUTH_KEY"]}'
unset TAILSCALE_AUTH_KEY
```

The upload command requires `TAILSCALE_AUTH_KEY` to be set for a first upload.
Then deploy with the existing aggregate playbook and its required image tag:

```sh
export OILSCOPE_IMAGE_TAG=<published-image-tag>
ansible-playbook oilscope.platform.deploy_workloads \
  -i infrastructure/ansible/inventory/oilscope.yml \
  -e project_config_path="$OILSCOPE_PROJECT_CONFIG"
```

For an existing K3s cluster, back up the datastore and plan a maintenance
window before changing node addresses: this playbook restarts K3s services as
each configuration changes. The aggregate play still runs database preparation
before the Tailscale/K3s play. A separate `deploy_k3s` run also installs
Tailscale first, provided the secret has already been uploaded.

## What stays on cloud networking

Bootstrap SSH still uses the public bastion and private node addresses.
Private cloud NAT remains needed for package downloads and Tailscale control
and relay connections. The optional public ingress node still serves the UI.
Managed PostgreSQL remains on its provider-private endpoint. In
`postgres_extensions` mode, the Compose-hosted database endpoint currently
uses the primary server's cloud-private `internal_ip`; cross-cloud application
pods cannot assume that address is reachable. This Tailscale change does not
alter database configuration. Existing provider-local K3s firewall allowances
are retained to avoid disrupting current bootstrap and same-cloud traffic;
they are candidates for a later, separately verified cleanup.

## Verification and troubleshooting

Run these on each K3s node (through the bastion as needed):

```sh
sudo systemctl status tailscaled
sudo tailscale status
sudo tailscale ip -4
sudo tailscale ping <other-k3s-node-name>
sudo awk '/^(node-ip|advertise-address|flannel-iface|server):/' /etc/rancher/k3s/config.yaml
sudo ss -tnp '( dport = :6443 or sport = :6443 or dport = :2379 or dport = :2380 )'
```

On the primary server, verify Kubernetes node addresses:

```sh
sudo k3s kubectl get nodes -o wide
sudo k3s kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}'
```

For a newly initialized Tailnet cluster, the `InternalIP` and `node-ip` values
should match `tailscale ip -4`; joining nodes should point at the primary
Tailscale IPv4. For a pre-existing etcd cluster, those values remain the
provider-private addresses until its separate migration. `tailscale ping` can
report a direct or relayed path; both use the private tailnet.

If a node does not join, inspect `systemctl status tailscaled` and
`journalctl -u tailscaled -n 100 --no-pager`, then `tailscale status`. Confirm
that its provider-scoped `tailscale-auth-key` secret exists, that the controller
can read it, that the key is valid and pre-authorized when required, and that
outbound HTTPS/DNS works. If a node joins but K3s cannot connect, check the
tailnet policy and `tailscale ping` before checking the K3s service logs. Do
not print or paste the auth key into diagnostic output.
