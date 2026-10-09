# Kubernetes modes and what switching costs

## What `managed_kubernetes` selects, and what it doesn't

`managed_kubernetes` (`false` or absent for the self-hosted k3s cluster, `true`
for Amazon EKS) chooses **who runs the control plane and where the nodes come
from**. Nothing else.

| | `false` (default) | `true` |
| --- | --- | --- |
| Control plane | three k3s servers with embedded etcd, on EC2 | EKS, run by AWS |
| Nodes | exactly three EC2 instances from `vms`, each with an Elastic IP | one EKS managed node group, sized by `kubernetes.eks.node_group` |
| Node access | SSH from `kubernetes.admin_allowed_cidrs` | none — no SSH, no Ansible over SSH, no `host_baseline` |
| Kubernetes API | `kubernetes.api_endpoint`, a DNS name this project publishes at the entry node | the endpoint AWS publishes for the cluster |
| Kubeconfig credential | a cluster-admin client certificate that does not expire | `aws eks get-token`, your own AWS identity, nothing stored |
| Ingress reachability | Traefik on host ports 80/443; DNS `A` to the entry node | Traefik behind a Network Load Balancer; DNS `CNAME` to it |
| Who publishes DNS | Terraform | `deploy_cluster`, because the load balancer has no name until then |
| etcd | yours, snapshots deferred | AWS's |
| Availability zones | one | one for the nodes; a second subnet exists only because EKS requires two |

**It does not select the database.** `managed_database` is a separate switch and
the two never read each other — see [database modes](database-modes.md). All
four combinations are valid configurations and `terraform plan` produces the
right resources for each. Deploying is narrower: `managed_database: false` has
no in-cluster PostgreSQL chart on **either** platform, so `deploy_cluster`
refuses it, naming
[step 27](k3s-implementation-steps.md#step-27--managed_database-false). Choosing
EKS neither fixes that nor forces `managed_database: true` in the file.

**It does not select the application.** The same images, the same Helm charts,
the same secrets, the same migration Job, the same ingress class and the same
operator console run on both. That is deliberate and it is what the switch is
worth: the list of things that differ is in [one table below](#what-differs-in-practice).

**It does not migrate anything.** See
[switching on an existing deployment](#switching-on-an-existing-deployment).

### Omitting it

An omitted `managed_kubernetes` means `false`. A configuration written before
this key existed validates unchanged and keeps deploying k3s. Both committed
examples set it anyway, because a reader should not have to know the default.

### EKS is AWS-only

`managed_kubernetes: true` with `default_cloud` of `gcp` or `azure` is rejected
three times over — by the schema, by `bootstrap_eks`, and by `deploy_cluster` —
and never quietly downgraded to k3s. GKE and AKS are separate work, as the rest
of the non-AWS trees already are.

## Configuration

Only these keys change between the modes. Everything else in the file is shared.

| Key | `false` | `true` |
| --- | --- | --- |
| `vms` | required, exactly three `kubernetes`-role nodes | must be absent or empty |
| `kubernetes.version` | required, pinned k3s release | unused; `kubernetes.eks.version` instead |
| `kubernetes.entry_node` | required | unused — no node is special |
| `kubernetes.ssh_address_mode` | required | unused |
| `kubernetes.api_endpoint` | required | unused — AWS publishes one |
| `kubernetes.pod_cidr` | required | unused — the VPC CNI gives pods subnet addresses |
| `kubernetes.etcd` | required | unused — AWS runs etcd |
| `kubernetes.eks` | unused | required |
| `kubernetes.service_cidr` | required | required, and must not overlap `clouds.aws.vpc_cidr` |
| `kubernetes.admin_allowed_cidrs` | SSH and the API | the API only |
| `clouds.aws.eks_network` | unused | required |
| `ingress.endpoint_mode`, `kubernetes.api_endpoint_mode` | `node` | `load_balancer` |

Two keys stay required in both modes and are **unused** on EKS, which is worth
knowing before you spend time on them: `ssh_users` (nothing is created to log
into) and `network.ui_public_ports` (the load balancer controller opens the
ports it needs on the security group EKS owns).

### The `kubernetes.eks` block

```json
"kubernetes": {
  "eks": {
    "version": "1.34",
    "public_api_access": true,
    "admin_principal_arns": [],
    "node_group": {
      "size": "small",
      "disk_size_gb": 60,
      "desired_size": 3,
      "min_size": 2,
      "max_size": 4,
      "capacity_type": "ON_DEMAND",
      "ami_type": "AL2023_x86_64_STANDARD"
    }
  },
  "admin_allowed_cidrs": ["192.0.2.10/32"],
  "api_endpoint_mode": "load_balancer",
  "service_cidr": "10.43.0.0/16",
  "namespace": "oilscope"
}
```

`node_group.size` is a key into `size_map`, resolved through its `aws` branch
exactly as a VM's `size` is, so instance types stay named in one place.

`ami_type` has to match the architecture of both the instance type `size_map`
resolves to **and** every image in `registry.image_digests`. Nothing checks
either: an ARM node group pulling amd64 images produces pods stuck in
`CreateContainerError`, with the architecture mismatch several lines into the
kubelet's message.

`public_api_access: false` closes the public endpoint. The private endpoint is
always on, which is how nodes reach the API; with the public one closed, no
operator can reach the cluster without a route into the VPC, and there is no
bastion in this design to provide one.

`admin_principal_arns` grants cluster administrator access through an EKS access
entry, *in addition to* the identity that runs `terraform apply`, which the module
always creates an entry for itself.

That last part is explicit on purpose, and it is worth knowing why.
`bootstrap_cluster_creator_admin_permissions` — the AWS feature that grants the
creating principal access — **defaults to `false` in the Terraform provider**, not
to the API's `true`. The first cluster built from this module relied on that
default and ended up with access entries for nothing but the EKS service-linked
role and the node role, so every `kubectl` call returned a Kubernetes `401
Unauthorized` and the cluster could not be reached at all. The module now sets the
flag explicitly to `false` and derives an access entry from `aws_caller_identity`,
so access is always visible in the plan rather than inherited from a provider
default. An assumed-role ARN is rewritten to its role ARN, which is the form an
access entry accepts.

**An access entry is the only way back in.** There is no `aws-auth` ConfigMap to
edit: `authentication_mode` is `API`. If the applying identity is lost and no
other principal has an entry, the cluster is unreachable and has to be replaced —
so name at least one role somebody else controls here, rather than relying on the
automatic entry for whoever happened to apply. Listing the applying identity
explicitly is harmless; the set is de-duplicated.

### `clouds.aws.eks_network`

```json
"eks_network": {
  "secondary_subnet_cidr": "10.0.4.0/24",
  "secondary_availability_zone": "eu-central-1b"
}
```

EKS requires the control plane to see at least two availability zones. The node
group and the load balancer both stay in the primary zone, so this second subnet
normally carries nothing. It exists because the API refuses a single-subnet
cluster, and it is kept empty on purpose: the EBS volumes RabbitMQ and Redis use
are zonal, and a node group spanning two zones would let a pod be scheduled
where its volume cannot follow.

The CIDR must be inside `clouds.aws.vpc_cidr` and must overlap neither
`network.workload_subnet_cidr` nor either `clouds.aws.rds_network` subnet.
Nothing checks that; an overlap fails at `apply` with an AWS error about the
CIDR, which is at least loud.

## Prerequisites

Both modes need AWS credentials, the `aws` CLI, `helm`, `kubectl` and
`CLOUDFLARE_API_TOKEN` when `cloudflare.enabled` is true.

| | `false` | `true` |
| --- | --- | --- |
| `OILSCOPE_SSH_KEY` | **required** — every node is reached directly | not used |
| `aws` on `PATH` at `kubectl` time | only for `ecr get-login-password` | **required** — the kubeconfig shells out to it on every call |
| An SSH key in `ssh_users` matching your login | required | not used |

## Deploying

The two sequences differ in one step. Everything before and after it is the same.

```sh
export OILSCOPE_PROJECT_CONFIG="$PWD/project-config.json"
export CLOUDFLARE_API_TOKEN=...
export AWS_PROFILE=oilscope

# 1. Infrastructure, including the empty secret containers
terraform -chdir=infrastructure/terraform apply

# 2. Put a value in every container - see docs/secrets.md
ansible-playbook oilscope.platform.upload_secret_versions \
  -e secret_versions_config_file="$OILSCOPE_PROJECT_CONFIG"

# 3a. managed_kubernetes false - form the cluster over SSH
export OILSCOPE_SSH_KEY="$HOME/.ssh/oilscope_ed25519"
ansible-playbook oilscope.platform.bootstrap_k3s \
  -i infrastructure/ansible/inventory/oilscope-aws.yml \
  -e project_config_path="$OILSCOPE_PROJECT_CONFIG"

# 3b. managed_kubernetes true - the cluster already exists; take access to it
ansible-playbook oilscope.platform.bootstrap_eks \
  -e project_config_path="$OILSCOPE_PROJECT_CONFIG"

# 4. Build and push the images; the workflow prints each digest
git tag pavlo-v1.0.0 && git push origin pavlo-v1.0.0

# 5. Paste the digests into registry.image_digests and apply again
terraform -chdir=infrastructure/terraform apply

# 6. Platform and application - the same playbook either way
ansible-playbook oilscope.platform.deploy_cluster \
  -e project_config_path="$OILSCOPE_PROJECT_CONFIG"
```

Step 3b takes no `-i`: there are no hosts to discover, and pointing the AWS
inventory at an EKS configuration finds nothing by design. Running the wrong
bootstrap for the configuration is refused rather than silently doing nothing —
that refusal exists because `bootstrap_k3s` against an EKS configuration would
otherwise skip every play and report success.

`oilscope.platform.deploy_k3s` still works and is now a one-line alias for
`deploy_cluster`. The playbook was always `hosts: localhost` against a
kubeconfig, which is why it needed so little changing.

In EKS mode step 6 additionally:

1. installs `aws-load-balancer-controller` into `kube-system`, pinned in
   `infrastructure/helm/versions.yml`, before Traefik, because the controller's
   mutating webhook has to be serving when Traefik's `Service` is created;
2. waits for that `Service` to report a load balancer hostname;
3. publishes the `CNAME` records, when `cloudflare.enabled` is true, before
   anything waits on a certificate.

### Why Ansible publishes DNS on EKS and Terraform does on k3s

The load balancer is created by the controller from Traefik's `Service`, so its
DNS name does not exist while `terraform apply` is running and cannot be put in
a record then. Terraform's `cloudflare_dns` module therefore creates nothing in
this mode and its `dns` output says `managed_by: "ansible"`.

The cost is that the same record is owned in different places depending on the
mode. The alternative — two owners in one mode — is worse. With
`cloudflare.enabled` false, `deploy_cluster` prints the name and the hostnames
that have to point at it, and stops short of the certificate wait only in the
sense that it tells you first; create the records then.

**A record left from the other mode blocks this.** DNS cannot hold a `CNAME` and
an `A` for the same name, so publishing over an entry-node `A` record fails.
`deploy_cluster` detects that and refuses, naming the hostnames, rather than
deleting a record that may still point at a live deployment. Delete them
deliberately when the self-hosted cluster is finished with.

### Operator access on EKS

`bootstrap_eks` writes `~/.kube/<name_prefix>-<environment>.yaml` — the same
path `bootstrap_k3s` writes, which is why `deploy_cluster` needs no new
knowledge of it. The file contains the endpoint, the cluster CA and an `exec`
credential plugin:

```yaml
users:
  - name: oilscope-prod
    user:
      exec:
        apiVersion: client.authentication.k8s.io/v1beta1
        command: aws
        args: [--region, eu-central-1, eks, get-token, --cluster-name, oilscope-prod, --output, json]
```

It holds **no credential**. Every call mints a short-lived token with your own
AWS identity, and access is revoked by removing the access entry rather than by
rotating a cluster CA. That is a straight improvement on the k3s file, which
carries a non-expiring cluster-admin client certificate with no revocation list.

It still is not merged into `~/.kube/config` and `KUBECONFIG` is still never
exported, for the same reason: an ambient context lets a stray
`kubectl config use-context` redirect a `helm upgrade`.

## What differs in practice

| Feature | On EKS |
| --- | --- |
| Ingress | The same Traefik release and the same `oilscope` ingress class, from `values/traefik-eks.yaml`: no host ports, a `LoadBalancer` `Service`, NLB with pod-IP targets. The entrypoint-level HTTPS redirect, the access log format and the resources are identical, so the ACME solver and every chart `Ingress` are untouched. |
| DNS | `CNAME` to the load balancer, published by Ansible. No `api` record: the API endpoint is a name AWS owns. |
| TLS | cert-manager, the `letsencrypt` ClusterIssuer and HTTP-01 unchanged. The NLB forwards port 80, so the solver is reached. |
| Storage | The same `aws-ebs-csi-driver` chart and the same `oilscope-gp3` class, which both StatefulSets name explicitly. Its controller's credentials come from Pod Identity rather than the node role. `bootstrap_eks` clears the default annotation on the `gp2` class EKS ships, so there is exactly one default. |
| Registry | The same ECR repositories, the same pull secret seeded at deploy time, the same refresh CronJob. Its credential comes from Pod Identity. |
| Secrets | Unchanged. Resolved by the operator with their own identity and written into namespace-scoped Secrets. |
| Monitoring | The in-cluster `cluster-metrics` CronJob and its four CloudWatch alarms work, through Pod Identity. RDS metrics and the synthetics canary work. **Node CloudWatch agent metrics, the per-instance EC2 alarms and the Traefik access-log group do not**: they are produced by the `monitoring_agent` role over SSH and by `aws_instance` dimensions, and EKS nodes are reached by neither. |
| Headlamp | Unchanged in `token` mode. In `oidc` mode the API server is configured by Terraform's `aws_eks_identity_provider_config`; `configure_k3s_oidc` refuses to run, because there is no server to write a drop-in on. Its source allow-list depends on client IP preservation — see below. |
| etcd snapshots | Not applicable. AWS runs the control plane; `kubernetes.etcd` is unread. |
| Node break-glass | None. There is no SSH, and this project adds no SSM agent configuration. A broken node is replaced by the node group. |

### Client IP preservation, and what silently breaks without it

Traefik binds host ports on k3s, so it sees the real client address. Behind an
NLB with **IP targets, client IP preservation is off by default**: every request
arrives from the load balancer's own ENI address, and Traefik logs and acts on
that instead.

That is not cosmetic. `headlamp.allowed_cidrs` (defaulting to
`kubernetes.admin_allowed_cidrs`) is enforced by a Traefik `IPAllowList`
middleware whose reject status is **404**, so with preservation off the console
answers `Not Found` to everybody, including you, while running perfectly. The
access log is misleading in the same way: every line records the load balancer.

`values/traefik-eks.yaml` therefore sets

```yaml
service.beta.kubernetes.io/aws-load-balancer-target-group-attributes: preserve_client_ip.enabled=true
```

Confirm it is working before trusting any source-based rule. This should print
one value, your own address, not a `10.x` one:

```sh
kubectl --kubeconfig ~/.kube/<prefix>-<env>.yaml -n kube-system \
  logs -l app.kubernetes.io/name=traefik --tail=200 \
  | grep -o '"ClientAddr":"[0-9.]*' | sort -u
```

The trade-off it buys: with preservation on, a client inside the same VPC
reaching the ingress through the load balancer can hairpin and fail. Nothing
here does that — the services reach each other through cluster Services — but a
future in-cluster job calling `https://<ingress.hostname>` would.


### IAM: Pod Identity instead of the node role

On k3s, the EBS CSI controller, the metrics CronJob and the registry refresh all
authenticate as the **node instance role** through IMDS, which means every pod on
the node inherits those permissions — a tradeoff
[`k3s-deployment.md` states plainly](k3s-deployment.md#the-csi-driver-runs-as-the-node-not-as-itself)
and cannot close.

On EKS each gets its own role, bound to its namespace and service account by an
`aws_eks_pod_identity_association`:

| Namespace | Service account | Permissions |
| --- | --- | --- |
| `kube-system` | `ebs-csi-controller-sa` | `AmazonEBSCSIDriverPolicy` |
| `kube-system` | `aws-load-balancer-controller` | the upstream controller policy, verbatim |
| `kubernetes.namespace` | `<name_prefix>-cluster-metrics` | `cloudwatch:PutMetricData`, scoped to one namespace |
| `kubernetes.namespace` | `<name_prefix>-registry-refresh` | ECR pull on this project's repositories |

Pod Identity needs no annotation on the service account, which is why the Helm
charts are byte-identical between the modes. The node role itself carries only
`AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy` and
`AmazonEC2ContainerRegistryPullOnly` — the last one because the core addons' own
images come from an AWS-owned ECR registry that needs authentication.

The load balancer controller's policy is the upstream
`docs/install/iam_policy.json` for the pinned release, copied verbatim to
`modules/aws/eks/policies/load-balancer-controller.json` so it can be diffed
against upstream on an upgrade. It is an inline role policy, not a managed one,
so nothing in the account outlives the cluster.

### Core addons are not pinned

`vpc-cni`, `kube-proxy` and `coredns` are left at the versions EKS installs with
a new cluster, and only `eks-pod-identity-agent` is declared. That is the one
place this work departs from the project's pin-everything habit, and it is a
deliberate limit on scope rather than a judgement that pinning is wrong. The
consequence to know: a cluster created six months from now gets different addon
versions from one created today, and nothing in the repository records which.

## Cost

EKS is more expensive than k3s for the same workload, which is the main reason
`false` stays the default:

| | `false` | `true` |
| --- | --- | --- |
| Control plane | none — it runs on the three nodes you already pay for | an hourly per-cluster charge |
| Load balancer | none | one NLB, hourly plus capacity units |
| Nodes | three `small` instances | `node_group.desired_size` instances of the same tier |
| Elastic IPs | three, free while attached | none |

Set `budgets.aws.enabled` before the first EKS apply rather than after. Nothing
in this repository caps spend.

## Switching on an existing deployment

**Changing the flag builds a second, empty cluster and abandons the first. It
migrates nothing.** This is the section to read twice.

`terraform apply` after the change plans a large replacement — on the k3s-to-EKS
direction, every instance, every Elastic IP, the node role and the node security
group are destroyed, and a cluster, node group, four roles and a subnet are
created. Verify that with `terraform plan` before believing any of it; the plan
is the only accurate statement of what your deployment will do.

What survives, and what does not:

| | Survives | Why |
| --- | --- | --- |
| RDS instance and its data | **Yes** | `managed_database` governs it and did not change |
| Secret containers and their values | **Yes** | `secret_mappings` governs them and did not change |
| ECR repositories and images | **Yes** | the registry is independent of both switches |
| RabbitMQ messages | **No** | a new cluster, a new volume, an empty broker |
| Redis sessions | **No** | same; every signed-in user is signed out |
| Persistent volumes | **Not reattached** | `reclaimPolicy: Retain` keeps the EBS volumes, but nothing binds them to the new cluster. They are left behind, still billed, and reusing one means creating a PV by hand against its volume ID |
| TLS certificates | **No** | cert-manager issues new ones. Let's Encrypt allows five duplicates per week; a few switches exhaust that and the site serves an untrusted certificate until it resets |
| DNS records | **Changed type** | `A` to `CNAME` or back, and the old record blocks the new one until deleted |
| The old cluster | **Yes, and it keeps costing money** | destroying it is a separate, deliberate `apply` |

A safe-ish order, if you are doing it anyway:

1. `terraform plan` and read it. If the plan destroys the database, stop:
   `managed_database` changed too, and
   [database modes](database-modes.md#database-mode-switch-or-the-first-cutover-from-pgmqsql-sessions)
   covers that case, which needs a backup first.
2. Back up anything in RabbitMQ or Redis you care about. Usually nothing — the
   outbox is in PostgreSQL and sessions are disposable — but decide rather than
   assume.
3. `terraform apply`.
4. Run the new mode's bootstrap, then `deploy_cluster`.
5. Delete the DNS record of the old type when `deploy_cluster` names it.
6. Confirm the application is serving on the new cluster before deleting
   anything from the old one.
7. Release the left-behind EBS volumes once you are sure.

**Switching back does not restore data.** Neither direction does. Do not treat
the flag as a toggle between two deployments; treat it as a decision to build a
new one.

## When `bootstrap_eks` returns 401 Unauthorized

The cluster is up and reachable — a Kubernetes `401` means TLS and the endpoint
are fine and the *identity* was rejected. Two causes, in order of likelihood:

```sh
# 1. Which principals can authenticate at all?
aws eks list-access-entries --cluster-name <name_prefix>-<environment> --region <region>

# 2. Which identity is the kubeconfig's credential plugin actually using?
aws sts get-caller-identity
```

If your ARN is absent from the first list, nothing has granted you access. Add it
to `kubernetes.eks.admin_principal_arns` and `terraform apply`; that creates an
access entry and a policy association and touches nothing else — verify with
`terraform plan -target=module.aws_eks`, which must report adds only and **no
cluster replacement**.

If your ARN is present but the identity in step 2 is a different one, the exec
plugin is picking up different credentials from the environment. The kubeconfig
runs `aws eks get-token` with no `--profile`, so it uses whatever
`AWS_PROFILE`/`AWS_*` the calling shell exports — and `aws eks get-token`
succeeds for *any* valid identity, so a wrong-identity token is indistinguishable
from a missing grant until the API server rejects it. Export the same profile you
applied with.

## Destroying

`terraform destroy` alone does not finish, and does not clean up everything it
looks like it should. Four things are outside its knowledge, and two of them
block it.

**1. Delete the load balancer first.** The NLB is created by the controller from
Traefik's `Service`, so Terraform has no record of it. Its network interfaces
live in the node subnet, and a subnet with an ENI in it cannot be deleted — the
destroy fails on `DependencyViolation` after it has already torn down most of the
cluster.

```sh
helm --kubeconfig ~/.kube/<prefix>-<env>.yaml -n kube-system uninstall traefik
aws elbv2 describe-load-balancers --region <region> \
  --query 'LoadBalancers[].LoadBalancerName'
```

Wait until that query stops listing the load balancer before going on.

**2. Empty the registry.** `aws_ecr_repository` is declared without
`force_delete`, so a repository that still holds an image refuses to be
destroyed.

```sh
for r in ui history fetcher database; do
  ids=$(aws ecr list-images --repository-name "<prefix>/$r" --region <region> \
        --query 'imageIds[*]' --output json)
  [ "$ids" = "[]" ] || aws ecr batch-delete-image \
    --repository-name "<prefix>/$r" --region <region> --image-ids "$ids"
done
```

**3. Empty the Synthetics canary bucket**, if `monitoring.synthetics.enabled` is
true. `aws_s3_bucket.canary` sets `force_destroy = false`, and the canary writes
an artifact on every run, so the bucket is never empty by the time you destroy.
The bucket is not versioned, so a recursive remove is enough. Its name carries a
hash — read it from the error, or from `terraform output`:

```sh
aws s3 rm "s3://<prefix>-<hash>-health-<hash>" --recursive
```

This one surfaces late: the destroy tears down the cluster, the database and the
registry first and only then fails on `BucketNotEmpty`, so it looks like a
failed destroy when almost everything has in fact gone.

**4. Then destroy.**

```sh
terraform -chdir=infrastructure/terraform destroy
```

This takes the RDS instance with it, with `skip_final_snapshot = true` and
`delete_automated_backups = true` — **there is no snapshot and no undo**. The
secret containers go too, with `recovery_window_in_days = 0`, so their values are
gone immediately rather than after a recovery window.

**5. Clean up what survives.** Two EBS volumes outlive the cluster, because the
`oilscope-gp3` class is `reclaimPolicy: Retain` — deliberately, since with etcd
snapshots deferred they are the closest thing to a backup this deployment has.
They keep being billed until deleted.

```sh
kubectl --kubeconfig ~/.kube/<prefix>-<env>.yaml get pv \
  -o custom-columns='NAME:.metadata.name,VOL:.spec.csi.volumeHandle'   # before destroying
aws ec2 delete-volume --region <region> --volume-id vol-...
```

The DNS records also survive: in managed Kubernetes mode `deploy_cluster`
published them, not Terraform, so `destroy` does not remove them. Delete the
`CNAME`s by hand, or they point at a load balancer that no longer exists. The
kubeconfig at `~/.kube/<prefix>-<env>.yaml` is stale too.


## Configuration rules nothing enforces

In addition to
[the four the self-hosted mode has](k3s-deployment.md#configuration-rules-nothing-enforces),
EKS mode adds these. Each produces a cluster that half-works rather than an
error:

- **`clouds.aws.eks_network.secondary_subnet_cidr` must not overlap the workload
  or RDS subnets**, and must be inside `clouds.aws.vpc_cidr`.
- **`kubernetes.service_cidr` must not overlap `clouds.aws.vpc_cidr`.** EKS
  rejects an overlap at `apply`, so this one is at least loud.
- **`kubernetes.eks.node_group.ami_type` must match the architecture of the
  resolved instance type and of every published image.**
- **`node_group.min_size` must be at most `desired_size`, and `desired_size` at
  most `max_size`.** The schema checks each is a positive integer and nothing
  more.
- **`desired_size` must be at least 1 for anything to run**, and realistically
  at least 2: RabbitMQ, Redis, the three services, Traefik, the CSI controller,
  the load balancer controller and cert-manager do not fit comfortably on one
  `small` node.

Check these by eye. The schema cannot compare one part of a document with
another, and this project has no Terraform validations by house rule.
