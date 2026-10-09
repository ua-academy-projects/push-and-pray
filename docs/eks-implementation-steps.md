# `managed_kubernetes` — implementation steps

Adds a second Kubernetes hosting mode alongside the self-hosted k3s cluster, in
the same shape `managed_database` already has: one top-level JSON boolean that
selects between provisioning the platform yourself and letting the cloud provide
it.

| | `false` (default) | `true` |
| --- | --- | --- |
| Control plane | three k3s servers with embedded etcd, on EC2 | Amazon EKS |
| Nodes | three fixed EC2 instances with Elastic IPs | one EKS managed node group |
| Node access | SSH from `kubernetes.admin_allowed_cidrs` | none; no SSH, no Ansible over SSH |
| API endpoint | `kubernetes.api_endpoint`, DNS to the entry node | the EKS endpoint AWS publishes |
| Ingress reachability | DNS `A` to the entry node's Elastic IP | DNS `CNAME` to an NLB the AWS Load Balancer Controller creates |
| etcd | self-managed, snapshots deferred | AWS-managed |

Companion to [k3s-implementation-steps.md](k3s-implementation-steps.md), whose
house rules apply here unchanged and are restated below because they decide what
"good" looks like.

Record each step's outcome in [k3s-implementation-log.md](k3s-implementation-log.md)
before starting the next.

## House rules, restated

1. **No comments in code.** Terraform, Ansible YAML, Python, Go. Explanation
   goes in `docs/`. A wrong comment is deleted, not corrected.
2. **Module calls in `main.tf` pass only the config object and other modules.**
   A new module takes `variable "config"` plus module references.
3. **Root `locals` stay short.** Derivation happens inside each module.
4. **No tests, assertions or validations in Terraform or Ansible.** No
   `validation` blocks, no `precondition`, no `check`, no `assert` tasks, no
   `roles/*/tests/`. Refusing an unsupported combination with
   `ansible.builtin.fail` is the one established exception, already used for
   `managed_database: false` and for unsupported clouds in
   `roles/database_migrate/tasks/read_secret.yml`.

Rule 4 is why the validation coverage this work adds lives in `pytest` under
`infrastructure/tests/`, driving `project-config.schema.json` directly. That
directory is already in `pyproject.toml`'s `testpaths` and `jsonschema` is
already a dev dependency.

## Scope

**EKS is AWS-only.** `managed_kubernetes: true` with `default_cloud` of `gcp` or
`azure` is rejected by the schema, by Terraform's `default_cloud` gate, and by
the deploy playbook — never silently downgraded to k3s. GKE and AKS are separate
work, as the rest of the non-AWS trees already are.

The GCP and Azure module trees are not edited, not even for a one-line shim.

### The two flags stay independent

`managed_kubernetes` and `managed_database` never read each other. All four
combinations are valid configurations: they validate against the schema, and
`terraform plan` produces the right resource set for each.

What that does **not** change: `managed_database: false` has no implementation on
either Kubernetes platform. There is no in-cluster PostgreSQL chart — see
[step 27 of the k3s guide](k3s-implementation-steps.md#step-27--managed_database-false),
which records the decision not to build one and why. `deploy_cluster.yml`
therefore keeps refusing that branch, and the refusal now reads the same in both
Kubernetes modes rather than naming k3s. Choosing EKS does not change this and
does not force `managed_database: true` in the configuration — it is still the
operator's explicit choice, and still the only one that deploys.

### Omitting the flag

`managed_kubernetes` is **not** added to the schema's top-level `required` list.
An existing configuration that has never heard of it stays valid and keeps
deploying k3s. Every reader treats absent as `false`:
`try(var.config.managed_kubernetes, false)` in Terraform,
`k3s_project.managed_kubernetes | default(false) | bool` in Ansible.

Both committed examples set it explicitly anyway, and a third example is added
for the EKS mode.

---

## Step 1 — Schema: the switch, and making the k3s-only keys conditional

**File.** `infrastructure/terraform/project-config.schema.json`

**Do.**

1. Add the top-level property, not to `required`:

   ```json
   "managed_kubernetes": {
     "type": "boolean",
     "default": false,
     "description": "Kubernetes hosting selector: true provisions Amazon EKS in default_cloud, which must be aws; false or absent runs the self-hosted k3s cluster described by vms."
   }
   ```

2. Remove `vms` from the top-level `required` array. EKS has no `vms`.

3. Narrow `kubernetes.required` to the keys both platforms need:
   `["admin_allowed_cidrs", "service_cidr", "namespace"]`. The k3s-only keys —
   `version`, `entry_node`, `ssh_address_mode`, `api_endpoint`, `pod_cidr`,
   `etcd` — move into the conditional branch in step 4. They stay *described* in
   `properties`; only the requirement moves.

4. Add `kubernetes.eks`:

   ```json
   "eks": {
     "type": "object",
     "additionalProperties": false,
     "required": ["version", "node_group"],
     "properties": {
       "version": { "type": "string", "pattern": "^\\d+\\.\\d+$" },
       "node_group": {
         "type": "object",
         "additionalProperties": false,
         "required": ["size", "disk_size_gb", "desired_size", "min_size", "max_size"],
         "properties": {
           "size": { "type": "string", "minLength": 1 },
           "disk_size_gb": { "type": "integer", "minimum": 20 },
           "desired_size": { "type": "integer", "minimum": 1 },
           "min_size": { "type": "integer", "minimum": 1 },
           "max_size": { "type": "integer", "minimum": 1 },
           "capacity_type": { "type": "string", "enum": ["ON_DEMAND", "SPOT"], "default": "ON_DEMAND" },
           "ami_type": { "type": "string", "enum": ["AL2023_x86_64_STANDARD", "AL2023_ARM_64_STANDARD"], "default": "AL2023_x86_64_STANDARD" }
         }
       },
       "public_api_access": { "type": "boolean", "default": true }
     }
   }
   ```

   `node_group.size` is a key into `size_map`, exactly as a VM's `size` is, so
   the cloud-neutral tier stays the one place instance types are named.

5. Widen `kubernetes.api_endpoint_mode` and `ingress.endpoint_mode` from
   `const: "node"` to `enum: ["node", "load_balancer"]`. Each branch in step 4
   pins the right one. Both keys stay optional.

6. Add `clouds.aws.eks_network`, mirroring `rds_network`:

   ```json
   "eks_network": {
     "type": "object",
     "additionalProperties": false,
     "required": ["secondary_subnet_cidr", "secondary_availability_zone"],
     "properties": {
       "secondary_subnet_cidr": { "type": "string", "minLength": 1 },
       "secondary_availability_zone": { "type": "string", "minLength": 1 }
     },
     "description": "A second public subnet in a second availability zone. EKS requires the control plane to see at least two zones; the node group and the ingress load balancer stay in the primary zone so EBS volumes keep reattaching."
   }
   ```

**Done when.** `check-jsonschema` accepts every example, and the step 9 tests
pass.

## Step 2 — Schema: the branch rules

**File.** same.

**Do.** Append two `allOf` entries. Keep the existing seven untouched — the
`managed_database` rules stay exactly as they are, which is what keeps the flags
independent.

**The EKS branch**, `if managed_kubernetes is present and true`:

- top-level `default_cloud` must be `"aws"`
- `kubernetes` requires `["eks"]`
- `clouds.aws` requires `["eks_network"]`
- `kubernetes.api_endpoint_mode` and `ingress.endpoint_mode` are
  `const: "load_balancer"`
- `vms` gets `maxProperties: 0`

**The k3s branch**, `if not (managed_kubernetes is present and true)` — written
as `{"not": {"required": ["managed_kubernetes"], "properties": {"managed_kubernetes": {"const": true}}}}`, which matches both absent and `false`:

- top-level requires `["vms"]`
- `vms` gets `minProperties: 3`, `maxProperties: 3`
- `kubernetes` requires
  `["version", "entry_node", "ssh_address_mode", "api_endpoint", "pod_cidr", "etcd"]`
- `kubernetes.api_endpoint_mode` and `ingress.endpoint_mode` are
  `const: "node"`

**Done when.** The step 9 tests cover both branches and all four flag
combinations.

## Step 3 — Terraform: the EKS module

**New files.** `infrastructure/terraform/modules/aws/eks/{locals,cluster,iam,nodes,ingress,identity,outputs,variables}.tf`

**Do.**

`locals.tf` — `enabled = var.config.default_cloud == "aws" && try(var.config.managed_kubernetes, false)`, plus the settings pulled out of
`var.config.kubernetes.eks` and the instance type resolved through
`var.config.size_map[...].aws`.

`iam.tf` — the cluster role (`AmazonEKSClusterPolicy`, trust
`eks.amazonaws.com` for both `sts:AssumeRole` and `sts:TagSession`) and the node
role (`AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`). The node role
carries **no** EBS, CloudWatch or ECR policy: those go to Pod Identity in
`identity.tf`, so a pod no longer inherits them through IMDS the way it does on
k3s.

`cluster.tf` — `aws_eks_cluster` with:

- `access_config { authentication_mode = "API" }` with
  `bootstrap_cluster_creator_admin_permissions` set explicitly to `false`. The
  provider defaults it to `false` already, which cost a live cluster its first
  bootstrap: nothing granted the applying identity access and every call got a
  Kubernetes 401. Access is therefore granted entirely through access entries,
  and the module always creates one for the applying identity itself, derived
  from `aws_caller_identity` (an assumed-role ARN is rewritten to its role ARN,
  which is what an access entry accepts)
- `vpc_config` over both EKS subnets, `endpoint_private_access = true` and
  `endpoint_public_access` from `eks.public_api_access` with
  `public_access_cidrs = kubernetes.admin_allowed_cidrs`. Both endpoints on
  means nodes reach the API inside the VPC while the operator reaches it from an
  allow-listed address.
- `kubernetes_network_config { service_ipv4_cidr = kubernetes.service_cidr }`.
  `pod_cidr` is unused: the VPC CNI gives pods subnet addresses.
- `aws_eks_addon "eks-pod-identity-agent"`. The core addons (`vpc-cni`,
  `kube-proxy`, `coredns`) are left at the versions EKS installs with a new
  cluster, and that is recorded in `docs/kubernetes-modes.md` rather than pinned
  here.
- `aws_eks_access_entry` + `aws_eks_access_policy_association`
  (`AmazonEKSClusterAdminPolicy`) for each principal in a new optional
  `kubernetes.eks.admin_principal_arns`, so a second operator can be granted
  access without `apply` running as them.
- `aws_eks_identity_provider_config` when `headlamp.enabled` and
  `headlamp.auth_mode == "oidc"`. This is the EKS equivalent of
  `configure_k3s_oidc.yml`; on EKS the control plane is not reachable over SSH,
  so the OIDC wiring has to be Terraform's.

`nodes.tf` — one `aws_eks_node_group` in the **primary** subnet only, sized from
`eks.node_group`. Single-zone on purpose: the EBS volumes RabbitMQ and Redis use
are zonal, and spreading nodes across two zones would let a pod land where its
volume cannot follow. The second subnet exists only because EKS requires the
control plane to see two zones.

`identity.tf` — `aws_eks_pod_identity_association` for the four service accounts
that call AWS from inside the cluster, each with its own role:

| namespace | service account | permissions |
| --- | --- | --- |
| `kube-system` | `ebs-csi-controller-sa` | `AmazonEBSCSIDriverPolicy` |
| `kube-system` | `aws-load-balancer-controller` | the upstream controller policy, verbatim, in `policies/load-balancer-controller.json` |
| `kubernetes.namespace` | `<name_prefix>-cluster-metrics` | `cloudwatch:PutMetricData`, namespace-scoped |
| `kubernetes.namespace` | `<name_prefix>-registry-refresh` | `ecr:GetAuthorizationToken` |

Pod Identity needs no annotation on the service account, so the OilScope charts
are untouched. The same three OilScope workloads authenticate through the node
instance role over IMDS on k3s, which `docs/k3s-deployment.md` already calls out
as a tradeoff; on EKS that tradeoff is simply not taken.

The controller's policy is the upstream `docs/install/iam_policy.json` for the
pinned release, copied verbatim so it can be diffed against upstream on an
upgrade. It minifies to 5,196 characters, which fits an inline
`aws_iam_role_policy` (10,240) and would also fit a managed policy (6,144); it
is inline so that nothing in the account outlives the cluster.

There is **no `aws_lb` in Terraform.** The controller creates the NLB from
Traefik's `Service`, which has a consequence worth stating before it surprises
someone: the load balancer's DNS name does not exist until
`deploy_cluster.yml` has run, so **Terraform cannot publish the EKS ingress DNS
record**. Step 7a moves that record to Ansible for this mode only. The k3s mode's
records stay exactly where they are, in Terraform.

`outputs.tf` — `enabled`, `cluster_name`, `endpoint`,
`certificate_authority_data`, `node_role_name`, `node_role_arn`,
`cluster_security_group_id`, `node_group_name`, `subnet_ids`. Each is `null` or
empty when disabled, the way every other module in this tree reports "not my
cloud".

**Done when.** `fmt -check` and `validate` are clean.

## Step 4 — Terraform: gate the k3s resources, and share the network

**Files.** `modules/aws/network/*`, `modules/aws/vm/locals.tf`,
`modules/aws/registry/*`, `modules/aws/database/*`, `modules/aws/monitoring/*`,
`main.tf`

**Do.**

`network`: add `self_hosted_kubernetes` and `eks_enabled` to `locals`. Gate
`aws_security_group.kubernetes` on `self_hosted_kubernetes` — it describes k3s
host ports, etcd peers and Flannel, none of which exist on EKS, and leaving it
Terraform-owned on EKS would mean fighting the controller, which edits backend
security group rules. On EKS the only node security group is the one EKS creates
and the controller is free to manage it. Add `aws_subnet.eks_secondary` and its
public route-table association, set `map_public_ip_on_launch = local.eks_enabled`
on the workload subnet (nodes need a public address because there is no NAT
gateway, and on k3s the Elastic IPs do that job instead), and output
`eks_subnet_ids`.

Subnet tags, on EKS only: both subnets get
`kubernetes.io/cluster/<name_prefix>-<environment> = "shared"`, and **only the
primary subnet** gets `kubernetes.io/role/elb = "1"`. That tag is how the
controller discovers where to place the NLB; tagging both would give it a node in
an availability zone that holds no pods, and with cross-zone load balancing off
by default those connections fail.

`vm`: `local.aws_vms` becomes `{}` when `managed_kubernetes` is true. Everything
else in that module is already keyed off it, so the instances, the Elastic IPs,
the node role and the monitoring policy all disappear together.

`registry`: `aws_iam_role_policy.node_pull` currently attaches to
`var.vm.node_role_name`. It now attaches to whichever platform's node role
exists — the module takes `eks = module.aws_eks` as a second module reference
and picks. Repositories, lifecycle policy and the GitHub publisher role are
unchanged.

`database`: `aws_security_group.rds`'s ingress currently names
`var.network.security_group_ids.kubernetes`. It now names that group on k3s and
the EKS cluster security group on EKS, from a new `kubernetes = module.aws_eks`
input. The RDS subnets, subnet group, parameter group and instance stay keyed on
`managed_database` alone — which is what keeps a self-hosted database's
resources intact whichever Kubernetes platform is selected.

`monitoring`: `config.vms` becomes `optional(map(...), {})` and a
`managed_kubernetes = optional(bool, false)` is added to the typed `config`
object. `local.enabled` gains `|| var.config.managed_kubernetes`, so the
in-cluster `cluster-metrics` alarms still exist on a cluster that has no EC2
instances to alarm on. The per-instance EC2 alarms, the CloudWatch agent
configurations and the Traefik log group are all driven by `local.nodes` and so
become empty on EKS; that is correct and is written down in step 8 rather than
worked around.

`main.tf`: add `module "aws_eks"` taking `config` and `network`. Pass the new
module into `aws_registry`, `aws_database` and `cloudflare_dns`.

**Done when.** `validate` is clean and a plan of each example produces the
expected resource set.

## Step 5 — Terraform: outputs that describe either platform

**Files.** `infrastructure/terraform/outputs.tf`,
`modules/cloudflare/dns/*`

**Do.**

Rework the `cluster` output so nothing in it assumes k3s:

```hcl
{
  platform     = "k3s" | "eks"
  namespace    = ...
  ingress_host = ...
  api_endpoint = k3s ? config.kubernetes.api_endpoint : module.aws_eks.endpoint
  entry_node   = k3s ? config.kubernetes.entry_node : null
  nodes        = k3s ? { ... } : {}
  eks          = eks ? { cluster_name, endpoint, certificate_authority_data, region, node_group_name, ingress_dns_name } : null
}
```

`nodes` becoming `{}` rather than disappearing keeps every consumer's expression
valid. `entry_node` becoming `null` is deliberate: on EKS there is no node whose
loss takes the site down, and a consumer that still reads it should get an
obvious null rather than a plausible-looking name.

`cloudflare/dns`: the `config` object gains
`managed_kubernetes = optional(bool, false)`, and `kubernetes.entry_node` /
`api_endpoint` become optional strings. On EKS the module creates **no records at
all** and its `summary` output reports `managed_by = "ansible"`, because the
load balancer it would point at does not exist until the deploy playbook runs.
No `api` record is published in that mode either way — the EKS endpoint is a name
AWS already publishes and owns. The `headlamp` output keeps reporting the
hostname and whether it is managed, with a null address on EKS.

**Done when.** `terraform output -json` for an EKS configuration contains no
null-dereference and names no entry node.

## Step 6 — Ansible: bootstrap the selected platform

**Files.** new `playbooks/bootstrap_eks.yml`, new `roles/eks_kubeconfig/`,
`playbooks/bootstrap_k3s.yml`, `playbooks/configure_k3s_oidc.yml`,
`plugins/module_utils/oilscope_inventory.py`

**Do.**

`bootstrap_eks.yml` runs on `localhost` only — there is no host to SSH to. It
reads the Terraform `cluster` output the same way `deploy_k3s.yml` already does
(live, or from `terraform_outputs_path`), then:

1. `eks_kubeconfig` writes `~/.kube/<name_prefix>-<environment>.yaml` at mode
   `0600` — the **same path** `bootstrap_k3s.yml` writes, so the deploy playbook
   needs no new knowledge of where the file is. The difference is the user: an
   `exec` credential plugin running `aws eks get-token`, so the file holds no
   long-lived credential. That is strictly better than the k3s file, which
   carries a non-expiring cluster-admin client certificate.
2. Clears the `storageclass.kubernetes.io/is-default-class` annotation on the
   `gp2` StorageClass EKS ships. `oilscope-gp3` is named explicitly by both
   StatefulSets, so this is about not leaving two default classes behind for the
   next person; the deploy playbook already reports what it finds.

`bootstrap_k3s.yml` gains one `localhost` guard play that refuses to run when
`managed_kubernetes` is true, naming `bootstrap_eks` instead. Without it, the
playbook would quietly do nothing: the inventory discovers no instances, and
`deploy.sh`'s zero-host check is the only thing that would notice.

`configure_k3s_oidc.yml` gains the same guard. On EKS the API server's OIDC
configuration is `aws_eks_identity_provider_config` in step 3, not a drop-in
file on a node.

`oilscope_inventory.py`: `vms_for_cloud` and `validate_inventory_hosts` tolerate
an absent `vms` key, and `apply_direct_connection_vars` stops requiring
`OILSCOPE_SSH_KEY` when the inventory found no hosts at all. Today it raises
before looking, which would make `ansible-inventory` fail on a perfectly good
EKS configuration.

**Done when.** `ansible-lint` is clean and `bootstrap_eks.yml --check` runs to
the end against an EKS configuration.

## Step 7 — Ansible: one deployment path, two platforms

**Files.** new `playbooks/deploy_cluster.yml`, `playbooks/deploy_k3s.yml`

**Do.** `deploy_k3s.yml` already runs entirely on `localhost` against a
kubeconfig, so almost all of it is platform-neutral already. Move it to
`deploy_cluster.yml`, which is what it now is, and leave `deploy_k3s.yml` as a
one-line `import_playbook` so the command in every existing document and shell
history keeps working.

The changes inside it:

- Read `platform` from the `cluster` output and report it, instead of reporting
  `kubernetes.api_endpoint` unconditionally.
- On EKS only, install `aws-load-balancer-controller` into `kube-system` before
  Traefik, pinned from `versions.yml`, with `serviceAccount.create: true` and no
  role annotation — Pod Identity supplies the credentials.
- Install Traefik from `values/traefik.yaml` on k3s and `values/traefik-eks.yaml`
  on EKS. The EKS file is the same file with the host ports removed and
  `service.enabled: true` plus the NLB annotations
  (`aws-load-balancer-type: external`,
  `aws-load-balancer-nlb-target-type: ip`,
  `aws-load-balancer-scheme: internet-facing`). The ingress class, the
  entrypoint-level HTTPS redirect, the access log format and the resources stay
  identical, so cert-manager's HTTP-01 solver, every chart `Ingress` and the
  Headlamp middleware are unaffected.
- On EKS, wait for the Traefik `Service` to report
  `status.loadBalancer.ingress[0].hostname`, and report it.
- The Traefik coverage message currently ends "DNS points only at
  `entry_node`". On EKS it names the load balancer instead.
- The `managed_database: false` refusal keeps its behaviour and loses its
  k3s-specific wording. It now says that neither platform has an in-cluster
  PostgreSQL chart and points at the same step 27.
- Everything else — the EBS CSI chart, the storage-class check, secret
  mirroring, the database CA ConfigMap, the migration credential, the registry
  pull secret, `k3s_urls`, cert-manager, RabbitMQ, Redis, the application chart
  and Headlamp — is **unchanged**. The EBS CSI chart in particular works on EKS
  as-is, because Pod Identity supplies its controller's credentials without a
  values change.

`deploy_workloads.yml` and the `compose_project` roles are the Compose/VM path
and are not touched.

**Done when.** `ansible-lint` is clean, and `helm diff` against an existing k3s
cluster shows nothing, proving the k3s path did not change.

## Step 7a — Ansible: publish the EKS ingress DNS records

**New file.** `roles/cloudflare_records/`

**Do.** On EKS the load balancer's hostname is known only after Traefik is
installed, so `deploy_cluster.yml` publishes the `CNAME` records itself when
`cloudflare.enabled` is true: `ingress.hostname`, and `headlamp.hostname` when
the console is enabled. `ansible.builtin.uri` against the Cloudflare v4 API with
`CLOUDFLARE_API_TOKEN` from the environment — the same variable Terraform's
provider reads, and no new collection dependency. Look up the zone by
`cloudflare.zone_name`, look up any existing record by name and type, then create
or update it so re-running is idempotent. The token never appears in a log:
`no_log` on every task that carries it.

In k3s mode the role is not run at all; Terraform keeps owning those records.
Two owners for the same record in the same mode would be the real hazard, and
this avoids it — at the cost of the records living in different places depending
on the mode, which `docs/kubernetes-modes.md` states outright.

## Step 8 — Feature-by-feature audit

Each of these is checked and either made to work on EKS or recorded as not
applying. The audit itself lands in `docs/kubernetes-modes.md`.

| Feature | On EKS |
| --- | --- |
| Ingress | Same Traefik release and ingress class; its `Service` becomes an NLB with IP targets through the AWS Load Balancer Controller instead of binding host ports. |
| DNS | `CNAME` to the NLB instead of `A` to an Elastic IP, published by Ansible rather than Terraform. No `api` record. |
| TLS | cert-manager and the HTTP-01 solver unchanged; the NLB forwards port 80. |
| Persistent storage | The same `aws-ebs-csi-driver` chart and `oilscope-gp3` class. Node group is single-zone so volumes still reattach. `gp2` is un-defaulted. |
| Registry access | Same ECR repositories, same pull secret seeded at deploy time, same refresh CronJob — but its credential comes from Pod Identity instead of the node role. |
| Secrets | Unchanged. Resolved by the operator and written into namespace Secrets. |
| Monitoring | In-cluster `cluster-metrics` CronJob and its CloudWatch alarms work, via Pod Identity. RDS metrics and synthetics work. **Node CloudWatch agent metrics and Traefik access logs do not** — they are produced by the `monitoring_agent` role over SSH, and EKS nodes are not addressed that way. |
| Headlamp | Unchanged in `token` mode. In `oidc` mode the API server is configured by Terraform; `configure_k3s_oidc` refuses. |
| etcd snapshots | Not applicable; AWS runs the control plane. The `kubernetes.etcd` block is unused. |

## Step 8a — Helm catalogue and CI

**Files.** `infrastructure/helm/versions.yml`, new
`infrastructure/helm/values/traefik-eks.yaml`, `.github/workflows/pr-validation.yml`

**Do.** Add the controller to the pinned catalogue beside the other four
upstream charts, with the `verified_on` date moved forward:

```yaml
  load_balancer:
    repo: https://aws.github.io/eks-charts
    chart: aws-load-balancer-controller
    chart_version: "3.6.0"
    app_version: "v3.6.0"
```

Add `values/traefik-eks.yaml`. Extend the `helm` CI job to render both Traefik
values files and the controller chart, so `kubeconform` checks the EKS manifests
too and a values typo fails in CI rather than during a deploy.

## Step 9 — Validation coverage

**New file.** `infrastructure/tests/test_project_config_schema.py`

**Do.** Drive `project-config.schema.json` with `jsonschema`, from the committed
examples as fixtures. Cases:

- every committed example validates
- both existing examples set `managed_kubernetes` explicitly
- `managed_kubernetes` absent validates, and keeps the k3s requirements in force
- all four flag combinations validate
- `managed_kubernetes: true` with `default_cloud` `gcp` or `azure` is rejected
- `managed_kubernetes: true` without `kubernetes.eks` is rejected
- `managed_kubernetes: true` with a non-empty `vms` is rejected
- `managed_kubernetes: true` without `clouds.aws.eks_network` is rejected
- `managed_kubernetes: false` without `vms`, with two or four VMs, or without
  `kubernetes.entry_node` / `version` / `pod_cidr` / `etcd`, is rejected
- `managed_kubernetes: "true"` as a string is rejected
- the existing `managed_database` rules still hold in both Kubernetes modes:
  `true` still requires `database_profile` and `database_profile_map`, AWS still
  requires `clouds.aws.rds_network`

**Done when.** `uv run pytest` passes and `uv run ruff check .` is clean.

## Step 10 — Examples

**Files.** `project-config.example.json`,
`project-config.cloud-example.json`, new `project-config.eks-example.json`,
`.gitignore`

**Do.** Add `"managed_kubernetes": false` to both existing examples, beside
`managed_database`. Add a third example that is AWS + EKS + managed database:
no `vms`, a `kubernetes.eks` block, `clouds.aws.eks_network`,
`ingress.endpoint_mode: "load_balancer"`, no `entry_node`, no k3s `version`, no
`etcd`. Un-ignore it in `.gitignore` next to the other two.

## Step 11 — Documentation

**Files.** new `docs/kubernetes-modes.md`; `docs/k3s-deployment.md`,
`README.md`, `docs/dns.md`, `docs/headlamp.md`, `docs/monitoring.md`,
`docs/database-modes.md`

**Do.** `docs/kubernetes-modes.md` is the new primary document, shaped like
`database-modes.md`:

- what the switch selects and what it does not
- prerequisites per mode — EKS needs no `OILSCOPE_SSH_KEY`, needs the `aws` CLI
  on `PATH` for the kubeconfig's credential plugin, and needs the applying
  identity to be the one that later uses the cluster unless
  `admin_principal_arns` says otherwise
- the exact deployment command sequence for each mode, side by side
- cost: EKS adds an hourly control-plane charge and an NLB charge that k3s does
  not have, on top of the same per-node EC2 cost
- that the ingress DNS record is owned by Terraform on k3s and by Ansible on
  EKS, and why
- **what changing the flag on an existing deployment does.** Stated plainly: it
  builds a second, empty cluster and abandons the first. Nothing is migrated.
  Persistent volumes stay behind — `reclaimPolicy: Retain` keeps the EBS volumes
  but nothing reattaches them to the new cluster. RabbitMQ messages and Redis
  sessions are lost. The RDS instance and the secret containers survive untouched
  because neither flag governs them, so the application's data survives only to
  the extent it is in PostgreSQL. Certificates are re-issued, which runs into
  Let's Encrypt's five-duplicates-per-week limit. DNS changes record type. The
  old cluster keeps costing money until it is destroyed, and destroying it is a
  separate, deliberate `apply`.
- the step 8 audit table

Then the edits elsewhere: `k3s-deployment.md` gains a pointer and loses its
claim that the implementation is k3s-only; `README.md` gains a "Selecting
Kubernetes hosting" section beside "Selecting database hosting", and its
"`managed_database` must be `true` on AWS" paragraph is corrected to say that
this is about the missing in-cluster PostgreSQL chart rather than about the k3s
layout; `dns.md`, `headlamp.md` and `monitoring.md` get the entry-node and
node-agent assumptions scoped to k3s.

## Step 12 — Run the checks

```sh
terraform -chdir=infrastructure/terraform fmt -check -recursive
terraform -chdir=infrastructure/terraform validate
uv run ruff check . && uv run ruff format --check .
uv run pytest
yamllint -c .yamllint.yml .
ansible-lint            # in infrastructure/ansible
helm lint infrastructure/helm/charts/*
check-jsonschema --schemafile infrastructure/terraform/project-config.schema.json <each example>
```

`terraform plan` is **not** in that list: it needs real AWS credentials and
`CLOUDFLARE_API_TOKEN`, so it is reported as a check an operator has to run.
Nothing here applies infrastructure, destroys anything, or touches a live
deployment.
