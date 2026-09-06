# Multi-cloud (AWS) task — status & handoff

This file hands off an in-progress effort to whoever (human or agent) picks
it up next. The Terraform AWS foundation is implemented and validates, but
the bootstrap and Ansible gaps under **What's left** must be resolved before
the AWS deployment is operational.

## Goal

Add AWS as a second supported cloud alongside the existing GCP-only
Terraform setup, driven by the JSON config file. `default_cloud` picks the
cloud a VM deploys to by default, but **each VM may set its own `cloud`
field to override it** — so mixed GCP+AWS placement in one apply is
supported by the config/logic. As of now this is capability only: every VM
in the real config still resolves to the same cloud, and nothing actually
mixes yet. Cross-cloud connectivity (VPC peering/VPN between GCP and AWS,
needed so e.g. a `fetcher` on GCP could reach a `database` on AWS over
private IPs) stays deferred **until a VM's `cloud` actually diverges from
`default_cloud`** — at that point it becomes a real requirement, not an
edge case.

## Design, as actually built

- **Config shape**: `default_cloud`, `region` (a key into `region_map`),
  `size_map`/`region_map`/`disk_type_map`/`image_map` (abstract tier →
  native value per cloud), `clouds.gcp.project_id`, `clouds.aws.vpc_cidr`,
  `network` (`management_subnet_cidr`, `workload_subnet_cidr`,
  `ui_public_ports`), `ssh_users`, `registry`, `service_ports`, `vms`.
  `common_labels` was removed entirely (not just optional) — the labels it
  used to carry (`application`, `environment`, `managed_by`) are now a
  hardcoded local in `locals.tf`, not a config field.
- **Per-VM `cloud` override**: each VM may set `"cloud": "gcp"|"aws"`,
  overriding `default_cloud` for that VM only. Schema: optional property on
  the `vm` `$def`. `locals.tf`: `vm_clouds` resolves
  `try(vm.cloud, default_cloud)` once per VM; `resolved_vms` uses that
  (not the bare `default_cloud`) for the `size_map`/`disk_type_map`/
  `image_map` lookups and carries it forward as a `cloud` field.
  `gcp_vms`/`aws_vms` filter `resolved_vms` by that field.
  - **Known gap, not yet fixed**: `native_region` still resolves only
    against `default_cloud`, not per-VM. Harmless while nothing mixes;
    would need rethinking once a VM's `cloud` actually diverges.
- **`secret_mappings` is required again** (not optional) — must be present
  on every VM, `{}` if the VM has no secrets. This was tried as optional
  earlier and reverted for clarity: an explicit `{}` reads better than an
  absent key, and — more importantly — making it required let the schema
  add a real guard: `secret_mappings: { maxProperties: 0 }` when
  `role == "bastion"`, so a config mistake that gave bastion a secret can
  never pass validation. `secrets-gcp.tf` relies on this guard instead of
  filtering bastion out in Terraform too (a deliberate simplification —
  see git history/conversation for the tradeoff discussion).
- **Module `source` must be a static literal in Terraform** — there's no
  way for one module block to dynamically target GCP or AWS per VM. The
  mechanical answer is two filtered maps (`gcp_vms`/`aws_vms`) and two
  module blocks per resource type, each with `count`/`for_each` derived
  from those maps — see `main.tf`.
- **Per-cloud subnet placement lives inside each cloud's VM module**, not
  in `main.tf` — GCP and AWS don't share one rule. GCP: `bastion` →
  management subnet, everything else → workload. AWS: `bastion` **or**
  `ui` → management (public) subnet, everything else → workload (private)
  — because AWS subnets are public/private at the *subnet* level (routed
  to either an Internet Gateway or a NAT Gateway), not per-instance like
  GCP, so `ui` (needs to be internet-reachable) can't share a subnet with
  `database`/`history`/`fetcher` (must not be).
- **AWS Secrets Manager grants access through the *role*, not the
  *secret*** — the opposite of GCP's `google_secret_manager_secret_iam_member`
  (which attaches a binding to the secret resource). `secrets-aws.tf`
  builds one IAM policy per AWS VM that has secrets, attached to that VM's
  own IAM role, listing exactly the secret ARNs it needs.
- **AWS SSH key delivery is cloud-init `user_data`**, not a GCP-style
  platform mechanism (AWS has no equivalent of GCP's `ssh-keys` instance
  metadata). `modules/aws/templates/ssh-users.yaml.tfpl` renders a
  `users:`/`ssh_authorized_keys:` block per `ssh_users` entry.
  - **Note found along the way**: GCP's own `cloud-config.yaml.tftpl` /
    `bastion_startup_script` locals (in `modules/gcp/vm/locals.tf`) are
    dead code — computed but never wired into `google_compute_instance` at
    all. Ansible owns docker setup / deployment entirely; the AWS
    cloud-init template deliberately only handles SSH users, nothing else.
- **AWS security-group egress is explicit** — every VM security group allows
  outbound IPv4 traffic so the bastion can initiate SSH and workloads can use
  the NAT Gateway to reach package repositories, GHCR, and cloud APIs.

## Real values already gathered (don't re-ask for these)

- GCP `project_id`: `my-name-oilscope-dev`
- GCP region/zone: `europe-central2` / `europe-central2-a`; AWS region/AZ:
  `eu-central-1` / `eu-central-1a`
- GHCR repository: `ghcr.io/ua-academy-projects/push-and-pray`
- GHCR username: `Pavlobuch`
- `registry.image_sha`: must track a `main` commit that was actually built
  — see `.github/workflows/reusable-build-image.yaml` (tags images with
  `github.sha`).
- SSH public key file: `~/.ssh/petroscope_gcp_ed25519.pub`
- UI public hostname: `oilscope.skynet-zrg.pp.ua` (domain
  `skynet-zrg.pp.ua` is user-controlled)
- ACME/Let's Encrypt email: `pashque1991@gmail.com`
- AWS `vpc_cidr`: `10.10.0.0/16` (contains both subnet CIDRs,
  `10.10.0.0/24` management / `10.10.1.0/24` workload)
- Real secret IDs in use: `oilscope-db-password` (`POSTGRES_PASSWORD`, on
  `infra`/`history`/`ui`), `oilscope-ghcr-token` (`GHCR_TOKEN`, same three
  + `fetcher`), `oilscope-oilpriceapi-key` (`OILPRICEAPI_KEY`, `fetcher`
  only)

## AWS account prep — done manually

- IAM user (dedicated, not root) with programmatic access; access key in
  the user's password manager, not in this repo.
- AWS CLI configured as profile `oilscope`, region `eu-central-1`.
- Region/AZ/instance types confirmed available; `t3.small`/`t3.medium` are
  **not** AWS free-tier eligible (unlike GCP's always-free `e2-micro`).
- NAT strategy: **NAT Gateway** (AWS-managed). EIP quota confirmed clear.
- EC2 Key Pair `oilscope-operator` imported as a fallback/break-glass SSH
  path, independent of cloud-init.
- Ubuntu 26.04 AMI SSM path confirmed in `eu-central-1`:
  `/aws/service/canonical/ubuntu/server/26.04/stable/current/amd64/hvm/ebs-gp3/ami-id`
  → `ami-0f6301584b61253b1`.

## File layout (as actually built — note the folder rename)

Modules live under `modules/<cloud>/<resource>`, not the earlier
`modules/network-gcp`/`modules/vm-aws`-style flat names:

| Path | Status |
|---|---|
| `modules/gcp/network` | done (renamed from `modules/network`) |
| `modules/gcp/vm` | done (renamed from `modules/vm`; one relative path fixed after the move — see below) |
| `modules/aws/network` | done — `network.tf` (VPC + 2 subnets), `routing.tf` (IGW, EIP, NAT Gateway, 2 route tables), `security_groups.tf` (5 SGs), `outputs.tf`, `variables.tf` |
| `modules/aws/vm` | done — `variables.tf`, `locals.tf` (subnet/SG selection by role, cloud-init render), `main.tf` (IAM role + instance profile, EIP, AMI SSM lookup, `aws_instance`), `outputs.tf` (`name`, `internal_ip`, `public_ip`, `role_arn`, `role_name`) |
| `modules/aws/templates/ssh-users.yaml.tfpl` | done — SSH-users-only cloud-init |
| `main.tf` | done — 4 module blocks: `gcp_network`/`gcp_vm` (existing), `aws_network`/`aws_vms` (new), each AWS pair gated on `length(local.aws_vms) > 0` |
| `locals.tf` | done — `vm_clouds`, `resolved_vms`, `gcp_vms`/`aws_vms`, `native_region`, `bastion_vm`/`workload_vms`, `common_labels` |
| `providers.tf` / `versions.tf` | done — both `google` and `aws` providers configured, `hashicorp/aws ~> 6.63` added |
| `secrets-gcp.tf` (renamed from `secrets.tf`) / `secrets-aws.tf` | done — kept as two files, not modularized (deliberate: this logic is cross-cutting across all VMs of a cloud, modularizing would add an interface boundary without reducing complexity) |
| `project-config.schema.json` / `project-config.example.json` | done — dictionary-based shape, `cloud` override, mandatory `secret_mappings`, bastion secret guard |
| `outputs.tf` (root) | done — common VM outputs merge AWS and GCP; secret outputs are grouped by cloud |

**Bugs found and fixed along the way, worth knowing about if something looks odd in git blame:** a broken module path after the folder rename, a missing `../` in `modules/gcp/vm/locals.tf`'s relative path to the Ansible `compose_project` role (the module moved one directory deeper), several `module.vm`/`module.network` references left stale after renaming to `gcp_vm`/`gcp_network` (in `main.tf`, `outputs.tf`, `secrets-gcp.tf`), and assorted typos/missing `.id` accessors/missing `lookup()` defaults across `main.tf`, `modules/aws/network`, and `modules/aws/vm` during initial authoring. All confirmed fixed via `terraform validate` passing cleanly on the whole root config.

`outputs.tf` now merges the common AWS and GCP VM outputs. GCP-only values
such as network tags and service-account emails remain explicitly scoped to
GCP, while secret resource names are grouped by cloud.

## What's left

**Bastion SSH bootstrap — deliberately deferred.** The real configuration
sets the final bastion SSH port to `6666`, but a fresh Ubuntu instance listens
on port 22 until the Ansible bastion role changes `sshd`.

- AWS currently opens only the final port. The AWS network module has no
  temporary port-22 ingress rule controlled by
  `enable_bastion_ssh_bootstrap`, so the documented bootstrap sequence cannot
  yet be used for an AWS bastion.
- GCP has a temporary port-22 firewall resource, but the root `main.tf`
  argument that forwards `var.enable_bastion_ssh_bootstrap` to `gcp_network`
  is commented out. The bootstrap flag therefore currently has no effect on
  GCP either.

Terraform itself can still be planned and applied while this work is deferred.
Do not expect a newly created bastion to be reachable on port `6666` before
the bootstrap flow has been implemented and run. Setting the configured port
to 22 is the simplest temporary choice for a Terraform-only test deployment.

**AWS Ansible inventory — deliberately deferred.** The committed inventory
uses only `oilscope.platform.oilscope_gcp`; it cannot discover EC2 instances,
derive AWS host variables, or connect to AWS workloads through the bastion.
Terraform can be run independently, but Ansible deployment cannot target the
new AWS instances until an EC2 inventory path is added.

**Item 8 — Ansible `resolve_secrets` AWS branch — deliberately deferred.**
`infrastructure/ansible/oilscope/platform/roles/resolve_secrets` is
100% GCP-specific — it calls the GCE instance metadata server for an
access token, then Google Secret Manager's REST API directly (see
`tasks/main.yml`). Needs a path that reads AWS IMDSv2 instance metadata for
the EC2 role's temporary credentials and calls AWS Secrets Manager's
`GetSecretValue`, so that `secrets-aws.tf`'s IAM grants actually get used
by anything at deploy time.

**AWS break-glass key pair — imported but never attached.** The
`oilscope-operator` EC2 Key Pair (see "AWS account prep") was imported as a
fallback SSH path independent of cloud-init, but `modules/aws/vm`'s
`aws_instance.workload` has no `key_name` argument or variable at all. The
key pair currently isn't attached to any instance, so it does not actually
provide break-glass access. Needs an optional `key_name` variable added to
`modules/aws/vm`, wired to `aws_instance.workload`, and set for at least the
bastion in `main.tf`.

**AWS instances do not enforce IMDSv2.** `aws_instance.workload` in
`modules/aws/vm/main.tf` has no `metadata_options` block, so both IMDSv1 and
IMDSv2 are accepted. Matters for the deferred `resolve_secrets` AWS branch
(item 8 below), which is meant to read IMDSv2 metadata for the EC2 role's
temporary credentials. Needs `metadata_options { http_tokens = "required" }`
added to `aws_instance.workload`.

**AWS resources are inconsistently tagged.** `modules/aws/network` (VPC,
subnets, IGW, NAT Gateway, route tables, security groups) and the IAM
role/instance profile/EIP in `modules/aws/vm` carry zero tags — only
`aws_instance.workload` (via `var.labels`) and the Secrets Manager secrets
(`local.common_labels`) are tagged today. Needs `local.common_labels` passed
into `modules/aws/network` as `tags`, and a `labels`/`tags` variable added to
tag the IAM role, instance profile, and EIP in `modules/aws/vm`.

**Remote state currently unavailable — not related to this code:** the original
GCS bucket (`gs://my-name-oilscope-dev-tf-state`) fails with
`UserProjectAccountProblem` because billing is disabled for its owning project.
The GCS backend block has temporarily been removed so Terraform can use local
state. Re-enable project billing before migrating that local state back to GCS.

**Secret values — intentionally absent after Terraform apply.** Terraform
creates empty secret containers and grants access, but never writes secret
payloads into state. Before deploying workloads, populate the required AWS or
GCP secret versions for `oilscope-db-password`, `oilscope-ghcr-token`, and
`oilscope-oilpriceapi-key` through an operator workflow.

**Still deferred, unrelated to Terraform code:**
- Generating the actual GHCR PAT (username confirmed: `Pavlobuch`; scope
  needed: `read:packages` on `ua-academy-projects/push-and-pray`).

## Reference file locations

| What | Where |
|---|---|
| Real working config | `~/Desktop/project-config.new.json` — validates cleanly against the live schema |
| Live repo schema (dictionary-based, current) | `infrastructure/terraform/project-config.schema.json` |
| Live repo example config (current) | `project-config.example.json` (repo root) |
| Original real config (old shape, source of the real values above) | `~/Desktop/project-config.json` |
| SSH public key used throughout | `~/.ssh/petroscope_gcp_ed25519.pub` |
