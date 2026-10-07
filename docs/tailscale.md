# Private access with Tailscale

OilScope uses the public-IP bastion as a Tailscale subnet router for its cloud
VPC. Tailscale is not installed on the K3s nodes, and the bastion is not an exit
node. Its only advertised route is the `network.vpc_cidr` value from the project
configuration.

## Prepare the tailnet

Define a tag owned by tailnet administrators. The policy can also approve the
project VPC route automatically:

```json
{
  "tagOwners": {
    "tag:oilscope-bastion": ["autogroup:admin"]
  },
  "autoApprovers": {
    "routes": {
      "10.10.0.0/16": ["tag:oilscope-bastion"]
    }
  }
}
```

Add grants appropriate for the users and devices that should reach the private
subnet. Do not rely on route approval as authorization: route approval makes a
route usable, while grants control who may use it.

Generate an auth key with these properties:

- **Reusable**, so the same key can enroll a replacement bastion after a
  Terraform destroy and apply while the key remains valid.
- **Ephemeral**, so a destroyed bastion is automatically removed from the
  tailnet after it has been offline for a short period.
- Tagged with `tag:oilscope-bastion`.
- **Pre-approved** if tailnet device approval is enabled.

Reusable auth keys can enroll more than one device and therefore require
careful handling. Give the key a short practical expiry, revoke it when it is no
longer needed, and do not put it in `project-config.json`, Terraform variables,
Git, or a shell command line. The key's expiry controls new enrollments; a
running bastion keeps its persisted Tailscale identity and does not need the key
on later playbook runs.

Load it without placing the value in shell history, then configure the router:

```bash
export TAILSCALE_AUTH_KEY="$(cat)"
# Paste the key, then press Ctrl+D.

ansible-playbook oilscope.platform.configure_tailscale_subnet_router \
  -i infrastructure/ansible/inventory/oilscope.yml

unset TAILSCALE_AUTH_KEY
```

The machine should display an **Ephemeral** badge on the Tailscale admin
console's Machines page. When an expired or revoked reusable key can no longer
enroll a newly created bastion, generate a replacement with the same settings
and load it into `TAILSCALE_AUTH_KEY`.

If the route was not covered by `autoApprovers`, approve it from the bastion's
machine page in the Tailscale admin console. Linux clients must separately run
`sudo tailscale set --accept-routes`; Windows, macOS, iOS, and Android clients
accept subnet routes by default.

## Configure private DNS

Technitium runs as a Docker container on the bastion. It binds DNS and its web
console only to the bastion's private VPC address; Terraform does not open
either port on the public interface. The role creates exact authoritative zones
for the Headlamp, Homepage, and Technitium console hostnames and points each
name at both K3s agent addresses. Exact zones avoid overriding the public parent
zone, so the public application hostname continues to resolve through
Cloudflare.

Set unique private hostnames in `project-config.json`:

```json
"private_services": {
  "headlamp": {
    "hostname": "headlamp.airaware.pp.ua"
  },
  "homepage": {
    "hostname": "homepage.airaware.pp.ua"
  },
  "technitium": {
    "hostname": "technitium.airaware.pp.ua"
  }
}
```

Do not add public `A` or `AAAA` records for these names. Load the Technitium
administrator password without putting it in shell history and deploy it:

```bash
export TECHNITIUM_ADMIN_PASSWORD="$(cat)"
# Paste a strong password, then press Ctrl+D.

ansible-playbook oilscope.platform.configure_private_dns \
  -i infrastructure/ansible/inventory/oilscope.yml

unset TECHNITIUM_ADMIN_PASSWORD
```

The role stores the password in a root-only file on the bastion because the
container needs it after a restart. Re-export the same password whenever
Ansible must reconcile the zones. The direct Technitium console at
`http://10.10.0.4:5380` is a recovery path from an authorized tailnet device;
it is intentionally unavailable through the bastion's public IP. Normal access
uses `https://technitium.airaware.pp.ua` through private K3s ingress.

In the Tailscale admin console, open **DNS**, add `10.10.0.4` as a custom
nameserver, and restrict it to `headlamp.airaware.pp.ua`. Add the same resolver
again for `homepage.airaware.pp.ua` and `technitium.airaware.pp.ua`. Do not
configure it as a global nameserver: this Technitium instance denies recursive
lookups and is only authoritative for those exact private zones.

Test from Windows with Tailscale connected:

```powershell
Resolve-DnsName headlamp.airaware.pp.ua
Resolve-DnsName homepage.airaware.pp.ua
Resolve-DnsName technitium.airaware.pp.ua
```

Each lookup should return the two private agent addresses, `10.10.1.20` and
`10.10.1.21`. `Resolve-DnsName dev.airaware.pp.ua` should still return the
public application address. Prefer `Resolve-DnsName` over `nslookup` for this
test because `nslookup` can bypass the operating system's split-DNS path.

## Publish Headlamp privately

Before the first add-on run, create a Cloudflare API token with
`Zone:DNS:Edit` and `Zone:Zone:Read` permissions restricted to
`airaware.pp.ua`. The token lets cert-manager complete DNS-01 validation; it
does not create a public Headlamp address record.

```bash
export CLOUDFLARE_API_TOKEN="$(cat)"
# Paste the token, then press Ctrl+D.

ansible-playbook oilscope.platform.deploy_k3s_addons \
  -i localhost, \
  -e k3s_addons_config_file="$PWD/project-config.json"

unset CLOUDFLARE_API_TOKEN
```

The playbook stores the token in a Kubernetes Secret, creates a production
DNS-01 ClusterIssuer, and creates the Headlamp Ingress. It also places one
Traefik replica on each K3s agent and sets `externalTrafficPolicy: Local`, which
prevents Kubernetes from replacing the original source address. The Ingress
has two Traefik middlewares: permanent HTTP-to-HTTPS redirection and an IP
allow-list containing only the bastion's private address. Tailscale subnet
routing uses SNAT, so connections from tailnet clients arrive with that source
address.

Verify the resources and certificate:

```bash
KUBECONFIG="$HOME/.kube/oilscope-dev.yaml" \
kubectl -n headlamp get ingress,middleware,certificate

KUBECONFIG="$HOME/.kube/oilscope-dev.yaml" \
kubectl -n headlamp create token headlamp-admin --duration=8h
```

Open `https://headlamp.airaware.pp.ua` from the tailnet device and paste the
temporary token. A `403 Forbidden` response indicates that DNS and routing work
but Traefik did not observe `10.10.0.4` as the request source. Verify that the
Traefik Service still uses `externalTrafficPolicy: Local` and that a ready
Traefik replica runs on each agent before changing the allow-list. Never solve
that by allowing the entire internet or the complete VPC.

Terraform permits K3s nodes to reach only the Technitium administration port
on the bastion. The same add-on playbook creates a private Technitium Ingress,
selectorless Service, and EndpointSlice, so
`https://technitium.airaware.pp.ua` receives a trusted DNS-01 certificate while
Technitium itself remains independent of K3s.

The add-on playbook also deploys Homepage at
`https://homepage.airaware.pp.ua`. Its private DNS zone, certificate, redirect,
and source-IP restriction use the same access pattern as Headlamp. The
dashboard checks OilScope, Headlamp, and Technitium and displays aggregate
cluster CPU and memory followed by the configured servers and agents.
Homepage's projected Kubernetes token is bound to a dedicated role that can
only read Nodes and Node Metrics. All three cards receive server-side health
indicators.
