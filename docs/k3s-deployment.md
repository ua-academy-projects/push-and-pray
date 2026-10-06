# k3s deployment

This document collects the rules the code does not state itself, because the
project keeps no comments in Terraform or Ansible and no validations in either.

## Before the first run

Four things have to be in the environment. None live in the repository.

```sh
export OILSCOPE_SSH_KEY="$HOME/.ssh/oilscope_ed25519"
export OILSCOPE_PROJECT_CONFIG="$PWD/project-config.new.json"
export CLOUDFLARE_API_TOKEN=...
```

AWS credentials come from the `oilscope` profile, which the `aws` provider names
directly — no `AWS_PROFILE` export needed for Terraform, but Ansible's boto3 and
the `aws` CLI still read it, so export it for those.

Azure credentials are needed for **every** `terraform plan`, including this one,
because Azure shares the single Terraform root.

## Deploying

The order matters, and the middle of it is awkward: the application cannot be
deployed until real image digests exist, and those come from pushing a Git tag.

```sh
# 1. Infrastructure, including the secret containers, which are created empty
terraform -chdir=infrastructure/terraform apply

# 2. Put a value in every container. Deployment fails on an empty one, and the
#    variable names come from the container IDs - see docs/secrets.md.
export OILSCOPE_OILPRICEAPI_KEY=... DB_PASSWORD_FETCHER=... \
       DB_PASSWORD_HISTORY=... RABBITMQ_PASSWORD=... REDIS_PASSWORD=...
ansible-playbook oilscope.platform.upload_secret_versions \
  -e secret_versions_config_file="$OILSCOPE_PROJECT_CONFIG" --check
ansible-playbook oilscope.platform.upload_secret_versions \
  -e secret_versions_config_file="$OILSCOPE_PROJECT_CONFIG"

# 3. The cluster, and a kubeconfig at ~/.kube/<name_prefix>-<environment>.yaml
ansible-playbook oilscope.platform.bootstrap_k3s \
  -i infrastructure/ansible/inventory/oilscope-aws.yml \
  -e project_config_path="$OILSCOPE_PROJECT_CONFIG"

# 4. Build and push the images. The workflow prints each digest in its summary.
git tag pavlo-v1.0.0 && git push origin pavlo-v1.0.0

# 5. Paste those digests into registry.image_digests and apply again: the
#    image references the Helm values use are built from them.
terraform -chdir=infrastructure/terraform apply

# 6. Platform and application
ansible-playbook oilscope.platform.deploy_k3s \
  -e project_config_path="$OILSCOPE_PROJECT_CONFIG"
```

Step 2 takes `secret_versions_config_file`, not `project_config_path` like the
other playbooks. Its default is empty, so passing the wrong name fails with
`Is a directory` rather than anything about a missing configuration. `--check`
uploads nothing and prints which environment variable feeds which container.

Step 5 is easy to miss. `registry.image_digests` feeds the Terraform `registry`
output, which is where the Helm values get their image references — so a digest
updated in the configuration but not re-applied deploys the old one. Confirm the
digests exist before deploying; ECR expires images and a reference to a deleted
one fails as an `ImagePullBackOff` inside a Helm pre-install hook, which surfaces
only as `timed out waiting for the condition`:

```sh
for s in ui history fetcher database; do
  printf '%-10s ' "$s"
  aws ecr describe-images --repository-name "oilscope/$s" \
    --query 'imageDetails[].[imageTags[0],imageSizeInBytes]' --output text
done
```

### Where the deployment reads Terraform's outputs

`deploy_k3s` runs `terraform output -json` against
`infrastructure/terraform` itself, so the addresses, image references and the
RDS administrator secret ARN are always the current ones.

Passing `-e terraform_outputs_path=/path/to/terraform-outputs.json` still works
and makes it read that file instead — useful when deploying from a machine with
no Terraform state. It is opt-in because a file is only as current as its last
export, and a stale one silently feeds old addresses. The RDS administrator
credential is the sharpest case: it lives in an AWS-managed secret whose name
embeds a per-instance UUID, so it changes every time the database is recreated.

The playbook prints which source it used.

Before applying, run the schema check by hand. Nothing else will:

```sh
uvx check-jsonschema \
  --schemafile infrastructure/terraform/project-config.schema.json \
  "$OILSCOPE_PROJECT_CONFIG"
```

Step 6 also deploys the operator console when `headlamp.enabled` is true, which
it is not by default. That path has an extra step before it — teaching the API
servers to validate operator tokens — and its own hostname, identity provider
and rollback rules. See [Headlamp, the operator console](headlamp.md).

### Seeing what a deploy would change

```sh
helm plugin install https://github.com/databus23/helm-diff   # once
helm diff upgrade oilscope infrastructure/helm/charts/oilscope \
  --kubeconfig ~/.kube/oilscope-prod.yaml -n oilscope
```

This is the only look-before-you-leap in the deployment path. There is no
preflight playbook and no assertions in Ansible, so `helm diff` is where drift
becomes visible.

## Rolling back

**The application** rolls back cleanly:

```sh
helm --kubeconfig ~/.kube/oilscope-prod.yaml -n oilscope history oilscope
helm --kubeconfig ~/.kube/oilscope-prod.yaml -n oilscope rollback oilscope <revision>
```

That reverts images, environment and ingress together. It does **not** revert a
database migration — migrations run as a pre-upgrade hook and are forward-only.
A rollback across a schema change needs the migration reversed by hand first.

**Everything else has no rollback procedure**, and that should be said plainly
rather than implied:

| Failure | What you have |
| --- | --- |
| Application release | `helm rollback` |
| A migration that applied badly | nothing automatic; forward-only SQL |
| A bad k3s configuration | re-run the bootstrap with a corrected value; the role restarts k3s on a config change |
| Lost etcd | **nothing** — snapshots are deferred, see below |
| Entry node lost | manual, see [dns.md](dns.md) |
| Terraform change | `terraform apply` of the previous revision, with the state caveats below |

With etcd snapshots deferred, losing the cluster means rebuilding it from
Terraform, Ansible and Helm. That works — the cluster is reproducible — but the
cert-manager ACME account key and issued certificates are not, and re-issuing
runs into Let's Encrypt's five-duplicates-per-week limit.

## Scope

The implementation targets **AWS only**. `modules/gcp/*` and `modules/azure/*`
still carry the previous Compose-era design and are converted separately, later.
Those trees are not edited here for any reason — not even to keep a plan running.

### The Azure modules are commented out, not deleted

`modules/azure/network/locals.tf` reads `network.management_subnet_cidr`, which
the k3s schema removed. A `locals` block is evaluated whatever value `count`
takes, so narrowing that module's `enabled` did not help and `terraform plan`
could not complete at all.

The six `module "azure_*"` blocks in `main.tf` and the outputs that read them in
`outputs.tf` are therefore **commented out**. Nothing under `modules/azure/` was
edited. Uncommenting them is one operation: both files, together.

This had a second effect worth knowing, because it is the opposite of what this
repository said for a long time. **An AWS plan no longer needs Azure
credentials.** The `azurerm` provider block is still present, but a provider with
no resource referring to it is never configured, so no authorizer is built.
`clouds.azure.subscription_id` can stay in the configuration; it is simply
unread.

GCP needs no credentials either. Its modules stay instantiated but resolve to
`count = 0` under `default_cloud: aws`, and that is enough: the provider is never
configured.

Both verified by planning with `AZURE_CONFIG_DIR` and `CLOUDSDK_CONFIG` pointed
at empty directories and no `ARM_*` or `GOOGLE_*` set. The only error was the
Cloudflare one below. Re-run that check before trusting this paragraph again, as
it turns on provider behaviour rather than on anything in this repository.

So an AWS change is verified like this:

```sh
terraform -chdir=infrastructure/terraform fmt -check -recursive
terraform -chdir=infrastructure/terraform validate
terraform -chdir=infrastructure/terraform plan -refresh=false \
  -var project_config_path="$CFG"
```

All three must now be **clean** — the plan completes. The only credentials it
needs are AWS (`AWS_PROFILE=oilscope`, pinned in the provider block) and
`CLOUDFLARE_API_TOKEN`, which the Cloudflare provider reads from the environment
and nowhere else. Without the token the `cloudflare_zone` data source fails with
a 403 naming a missing `X-Auth-Email` header, which looks like a credential-type
mismatch but means no token was found at all.

## One entry node, no load balancer

All three nodes are control-plane and worker, and all three have public Elastic
IPs — used for administration, for outbound access, and so that ingress can be
moved by hand.

Only one of them receives user traffic. `kubernetes.entry_node` names it, and both
`ingress.hostname` and `kubernetes.api_endpoint` publish a single DNS-only `A`
record pointing at that node's Elastic IP. Traefik binds host ports 80 and 443 and
routes onward through Kubernetes Services, so application pods schedule anywhere.
There is no NAT gateway: public nodes reach the internet through the internet
gateway directly.

### The firewall matrix

One security group covers all three nodes. Nothing validates it, so this is the
reference copy — `modules/aws/network/security_groups.tf` must match it:

| Port | Protocol | Source | Why |
| --- | --- | --- | --- |
| 22 | tcp | `kubernetes.admin_allowed_cidrs` | SSH. There is no bastion. |
| 6443 | tcp | `kubernetes.admin_allowed_cidrs` | Kubernetes API for the operator. |
| 6443 | tcp | the group itself | Agents reach the API server on peers. |
| 2379, 2380 | tcp | the group itself | Embedded etcd client and peer traffic. |
| 10250 | tcp | the group itself | Kubelet, for `kubectl logs`/`exec` and metrics. |
| 8472 | udp | the group itself | Flannel VXLAN. **UDP** — a tcp rule here produces a cluster where pods on different nodes cannot talk, with no other symptom. |
| `network.ui_public_ports` | tcp | `0.0.0.0/0` | Traefik. 80 is needed as well as 443, for the HTTP-01 challenge and the redirect. |
| all | all | — | Egress unrestricted: image pulls, Let's Encrypt, CloudWatch, Secrets Manager. |

Two things are deliberately absent. There is no rule for 10251/10252/10259/10257
— k3s runs the scheduler and controller manager in the same process as the API
server, bound to localhost. And there is no NodePort range: Traefik uses host
ports, so nothing needs 30000–32767 open.

Closing 80 breaks certificate issuance rather than just the redirect, because
`ingress.challenge_type` is HTTP-01.

### The limitation, stated plainly

**Losing the entry node takes down the website and the configured API endpoint,
even though the cluster itself is healthy.** etcd keeps quorum on the remaining
two, pods reschedule, workloads keep running — and no user can reach any of it,
because DNS still points at a dead address. There is **no automatic failover**.

Losing either other node costs nothing externally.

Recovery is manual, and one of:

1. Restore or replace the entry node, keeping its Elastic IP.
2. Move ingress to another node: repoint both `A` records at that node's Elastic
   IP, and — if Traefik is pinned rather than a DaemonSet — move Traefik there too.

Service returns no faster than `cloudflare.ttl`, which is why it is kept short.
`kubectl` has its own path: every node's address is a TLS SAN, so
`kubectl --server https://<surviving-node>:6443` works immediately without any DNS
change.

Do not describe this arrangement as highly available. It is a deliberate trade of
availability for cost and simplicity.

## Cluster bootstrap

`playbooks/bootstrap_k3s.yml` runs four plays against `k3s_servers`, which holds
all three nodes:

1. `host_baseline` on every node. Not `docker_engine` — k3s ships its own
   containerd, and a second runtime competes for the same images and cgroups.
2. The entry node initialises the cluster with `server --cluster-init`.
3. The token is read from that node and published as a fact.
4. The other two join with `server --server https://<entry private ip>:6443`,
   `serial: 1`, each waiting for its own etcd membership before the next starts.

The joins use the **private** address so cluster traffic stays inside the VPC,
and they are sequential because two nodes joining a one-member etcd at once can
race the membership change.

### The destructive mistake this guards against

**A second `--cluster-init` against a live cluster does not fail.** It creates a
new single-member etcd and orphans the existing data. There is no assertion to
catch it — house rule 4 — so the guard is conditional execution: the install
command carries `creates: /usr/local/bin/k3s`, and the init step additionally
skips when `/var/lib/rancher/k3s/server/db/etcd` already exists. Re-running the
playbook on a healthy cluster must be a no-op, and that is the property to check
after any change to the role.

### Why the worker label is applied with kubectl

The kubelet is not allowed to set its own `node-role.kubernetes.io/*` labels, so
putting them in `node-label` in the server configuration makes k3s refuse to
start. k3s applies `control-plane`, `master` and `etcd` itself, server-side.
`worker` is not one it applies, so the role adds it through the API after the
node is ready. Only `oilscope.io/entry-node` travels through `node-label`, which
is an unrestricted prefix.

### TLS SANs

The SAN list is `kubernetes.api_endpoint` plus **every** node's public and
private address. `api_endpoint` resolves only to the entry node, but the other
addresses have to be valid SANs so that
`kubectl --server https://<surviving-node>:6443` works when the entry node is
gone. Without them there is no break-glass path to the API.

### The token

`/var/lib/rancher/k3s/server/token` is generated on the entry node. It is
required to decrypt the bootstrap data inside an etcd snapshot, so **a snapshot
without the token is not a backup.** It never goes in the project configuration
or Git.

## The kubeconfig

The last play of `bootstrap_k3s.yml` fetches `/etc/rancher/k3s/k3s.yaml` from the
entry node and writes `~/.kube/<name_prefix>-<environment>.yaml` at mode `0600`.
Three things change on the way:

- the server address becomes `https://<kubernetes.api_endpoint>:6443` instead of
  the `127.0.0.1` k3s writes, which works only because that name is in the TLS
  SAN list;
- the cluster, user and context are renamed from k3s's `default` to
  `<name_prefix>-<environment>`, so the file cannot collide with anything else;
- `certificate-authority-data` is carried across unchanged. The hostname changed,
  the trust did not — never substitute `insecure-skip-tls-verify`.

**It is never merged into `~/.kube/config`, and `KUBECONFIG` is never exported.**
Every kubectl and helm call passes `--kubeconfig` explicitly. An ambient context
means a stray `kubectl config use-context` can point a `helm upgrade` at the
wrong cluster.

The file lives outside the repository on purpose. `.gitignore` also carries
`*.kubeconfig`, `kubeconfig`, `.kubeconfig/` and `**/kube/*.yaml` for anyone who
overrides the path inward — worth knowing that neither `gitleaks` nor
`detect-private-key` would catch it, because the key is base64 inside YAML rather
than a PEM block.

### Rotating it

The client certificate in that file is cluster-admin, issued by the cluster CA,
and **not short-lived**. There is no revocation list. If it leaks, containing it
means rotating the cluster CA — which is a disruptive operation, not a
credential swap. Treat the file accordingly: do not copy it into CI secrets, a
password manager shared with a wider group, or a second machine you do not
control.

## Helm from the operator's machine

Helm and kubectl run on your machine, never in the cluster. There is no CI
deployment path — accepted deliberately, in exchange for `helm diff` being
available before every apply.

`infrastructure/helm/versions.yml` pins every chart and image, with the date the
pins were checked against a live registry. Verified against:

| Tool | Version |
| --- | --- |
| helm | 3.19.4 |
| kubectl | 1.35.0 |
| kubernetes.core | 6.5.0 |

kubectl 1.35 against a k3s 1.36 server is one minor behind, which Kubernetes
supports. It stops being fine after another k3s bump.

`helm diff` is a Helm **plugin**, installed per machine — `requirements.yml`
cannot pin it:

```sh
helm plugin install https://github.com/databus23/helm-diff
```

Every Helm task passes `kubeconfig:` explicitly. `KUBECONFIG` is never exported
and the default context is never used, so a stray `kubectl config use-context`
cannot redirect a `helm upgrade`.

### Storage

`aws-ebs-csi-driver` provides one StorageClass, `oilscope-gp3`, created by the
chart itself rather than a separate manifest: gp3, encrypted, expandable,
`WaitForFirstConsumer`, `reclaimPolicy: Retain`, and marked default.

`WaitForFirstConsumer` rather than `Immediate` so a volume is created in the zone
the pod actually lands in. `Retain` so deleting a PVC leaves the disk behind —
which, with etcd snapshots deferred, is the closest thing to a safety net this
deployment has.

**k3s's `local-storage` is disabled**, alongside `traefik` and `servicelb`. Left
enabled it ships `local-path-provisioner` and marks *that* the default class, so
any PVC that does not name a class silently gets node-local disk. RabbitMQ's
volume would land on one node's filesystem and come up empty if the pod ever
moved. Disabling removes the wrong option rather than leaving two classes and an
annotation to manage.

The single-zone decision is what makes this work at all: all three nodes are in
one availability zone, so an EBS volume can reattach when a pod moves. In a 3-AZ
layout it could not, and single-instance RabbitMQ and Redis would be pinned to
whichever node first claimed their volume.

### Ingress

Traefik runs as a **DaemonSet** binding host ports 80 and 443 on every node, with
`service.enabled: false` — there is no Service at all, because there is no load
balancer to put in front of one and ServiceLB is disabled.

DNS points only at the entry node, so only that node receives traffic in normal
operation. The other two listen anyway, which is what makes the failover in
`docs/dns.md` a DNS change and nothing else.

The ingress class is named `oilscope` and is **not** the default. Every Ingress
names it explicitly, so nothing is routed by accident if a second controller is
ever installed.

Port 80 redirects permanently to 443. The ACME HTTP-01 solver is exempt from
that redirect by Traefik itself, so certificate issuance still works — this is
the piece that would break if the redirect were implemented as a middleware on
the router rather than on the entrypoint.

### The CSI driver runs as the node, not as itself

On EKS the driver would use IRSA — a role bound to its service account through
an OIDC provider registered for the cluster. **That is not available here.** The
OIDC provider from the registry work is for GitHub Actions; registering the k3s
cluster itself as an AWS identity provider is separate work nobody has done.

So the driver authenticates through the **node instance role**, which carries the
AWS-managed `AmazonEBSCSIDriverPolicy`. The managed policy is preferred over a
hand-written statement list because AWS maintains it as the driver's needs
change.

The tradeoff to be aware of: every pod on the node inherits that role through
IMDS, so any pod could call the EBS APIs, not only the CSI controller. Network
policy does not help — IMDS is a link-local address. Closing this properly means
either registering the cluster with AWS as an OIDC provider, or blocking IMDS
from pod networking and giving the driver credentials another way.

### Pulling images from ECR

ECR authorization tokens expire after **12 hours**, and k3s's `registries.yaml`
accepts only a static username and password. So there is nothing to configure
once and forget.

The arrangement is two halves:

- **Seeded at deploy time.** `deploy_k3s.yml` runs `aws ecr get-login-password`
  with the operator's identity and writes a `dockerconfigjson` Secret. This is
  what makes the first deployment work, before any schedule has fired.
- **Kept fresh by a CronJob**, every 8 hours, in the application namespace. An
  init container mints a token with the node role through IMDS, a second writes
  the Secret, and RBAC limits the ServiceAccount to creating secrets and
  modifying that one by name.

**The failure mode to know.** If the CronJob stops working, nothing breaks for
up to 12 hours and then **every image pull fails** — new pods, rescheduled pods,
replaced nodes. Running pods are unaffected because the image is already on the
node, which is what makes it easy to miss. Monitor the CronJob's failed-job
count, not just the application.

#### The better mechanism, and why it is not used

The correct answer is a kubelet credential provider: AWS's
`ecr-credential-provider` binary on each node, wired through
`--kubelet-arg=image-credential-provider-config=…`. The kubelet then mints a
token per pull from the node's IAM role, with nothing stored and nothing to
expire.

It is not used because the binary could not be sourced. Checked 2026-09-29:

| Source | Result |
| --- | --- |
| `artifacts.k8s.io/binaries/cloud-provider-aws/{v1.32…v1.36}/…` | 404 on every version |
| `kubernetes/cloud-provider-aws` GitHub releases | tags exist, no binary assets |
| `public.ecr.aws/eks/ecr-credential-provider` | no such manifest, any tag tried |

Building from source is possible and is the way to revisit this. Do not pick a
download URL by guesswork — a wrong one becomes a node that cannot pull, months
later, during a replacement.

### Redis runs without TLS inside the cluster

A deliberate deviation from the plan, which says to use verified TLS because
clients can be on another node.

RabbitMQ does use TLS: the broker already spoke AMQPS and the client contract is
`RABBITMQ_URL` with a CA file, so the leaf certificate from the internal CA is a
straight improvement over the Compose setup, which used the CA as the server
certificate.

Redis is different. The UI connects with a URL — `redis://:password@redis:6379/0`
— and switching to `rediss://` requires the CA bundle mounted into the UI pod and
the client configured to verify it. That is a change on both ends at once, and
the UI end belongs to the application chart. Doing half of it here would leave a
step that cannot be verified on its own.

So for now: authentication with `requirepass`, no transport encryption. Traffic
stays on the pod network and never leaves the VPC, but it does cross node
boundaries in the clear on a subnet shared with nothing else.

**Close this with the application chart**, where the URL, the CA mount and the
Redis `--tls-port` can change in one release.

### Why RabbitMQ and Redis use repository-owned charts

Checked 2026-09-27, and this is the reason the plan's warning about "image
availability without unexpected subscriptions" was justified:

| Reference | Result |
| --- | --- |
| `bitnami/rabbitmq:4.1.3-debian-12-r1` — the Bitnami chart's own default | **HTTP 404** |
| `bitnami/redis:latest` — the Bitnami chart's own default | HTTP 200, but a floating tag |
| `bitnamilegacy/rabbitmq:4.1.3-debian-12-r1` | HTTP 200 |

The Bitnami charts install and then fail to pull, because the versioned images
moved to `bitnamilegacy`, which is frozen and unsupported. The Redis chart
defaults to `latest`, which this project does not deploy.

So neither chart is used. Small repository-owned charts wrap the official
upstream images the project already pins for Compose — `rabbitmq.image` and
`redis.image` in the project configuration, both verified pullable. That reuses
version pins already maintained in one place instead of tracking a second set.

## Configuration rules nothing enforces

`project-config.schema.json` is the contract, but it is applied only when someone
runs it by hand:

```sh
uvx check-jsonschema \
  --schemafile infrastructure/terraform/project-config.schema.json \
  /absolute/path/project-config.json
```

There is no pre-commit hook and no CI job, because the real configuration lives
outside the repository and is never committed — a hook would only ever see the
examples. There are also no Terraform `validation` blocks or preconditions.

Four rules therefore hold only because an operator upholds them. Each produces a
cluster that half-works rather than an error:

- **`internal_ip` must be unique across the three nodes.** JSON Schema cannot
  compare sibling values; `uniqueItems` applies to arrays, not to the values of
  an object's properties.
- **Every `internal_ip` must fall inside `network.workload_subnet_cidr`.**
- **`kubernetes.pod_cidr`, `kubernetes.service_cidr` and the subnet CIDRs must
  not overlap.**
- **`kubernetes.entry_node` must name a key that exists in `vms`.** JSON Schema
  cannot compare one part of a document against another, so a typo validates
  cleanly and fails later as a missing map key in `terraform plan`.

Check all four by eye before applying. They are the most likely cause of a
cluster that forms but behaves strangely.

## Defaulting convention

Optional configuration keys are defaulted inside each module that reads them,
never once at the root — root `locals` stay short and modules stay
self-contained from a single `config` input. Nothing keeps the three cloud trees
agreeing on a default except this document, so record every optional key here as
it is added.

| Key | Default | Meaning |
| --- | --- | --- |
| `registry.location` | the deployment region resolved from `region_map` | Where the native registry lives. |
| `registry.create` | `true` | `false` references an existing registry instead of creating one. |

## Machine sizes are not equivalent across clouds

`size_map` keys name a tier, not a specification, and the tiers do not line up:

| tier | gcp | aws | azure |
| --- | --- | --- | --- |
| `micro` | `e2-micro` — 2 vCPU / 1 GiB | `t3.micro` — 2 / 1 | `Standard_DC1s_v3` — 1 / 8 |
| `small` | `e2-small` — 2 / 2 | `t3.small` — 2 / 2 | `Standard_DC1s_v3` — 1 / 8 |
| `medium` | `e2-medium` — 2 / 4 | `t3.medium` — 2 / 4 | `Standard_B2ms` — 2 / 8 |

The deployment uses `small`. On AWS that is 2 GiB per node. A k3s server with
embedded etcd takes roughly 0.6–0.9 GiB before any workload runs, leaving about
1.1–1.4 GiB for pods — enough in steady state, tight when one node is lost and
the remaining two carry RabbitMQ, Redis and every application pod. Measure
memory on the survivors during the one-node-loss test and resize if needed.

Note that `micro` and `small` currently map to the **same** Azure size, so the
tier is not a tier there at all. The Azure figures are unverified against current
Azure documentation and must be confirmed, and the duplication resolved, before
`default_cloud` is switched to azure. Nothing detects this: a `size` that means
one thing on AWS and something else on Azure validates cleanly.

## Secrets

`secret_mappings` is a top-level block keyed by workload (`history`, `fetcher`,
`ui`, `migration`), not a per-VM key. It maps environment variable names to
Secret Manager identifiers — never to values.

Terraform creates the secret containers. It no longer grants any VM identity
access to them: the operator resolves the values at deployment time with their
own cloud identity and writes them into namespace-scoped Kubernetes Secrets.

**Open question, to settle before the secrets are read in anger:** nothing now
grants read access to anybody. The previous design granted each VM's instance
role access to its own secrets, and that is gone. Whether the operator's identity
already has read access, or needs an explicit grant, is decided when the
resolution path is built.
