# k3s deployment — implementation log

The running record for [k3s-implementation-steps.md](k3s-implementation-steps.md).
Fill in a step's entry **before** starting the next step, while you still remember
what actually happened.

Three rules that make this log worth keeping:

- **Write what you did, not what the step said to do.** If they match, one line is
  enough. If they diverge, the divergence is the valuable part.
- **Record a problem even after you solve it.** A problem you hit and fixed in
  twenty minutes is the same problem the next person loses a day to.
- **A decision that contradicts the table below gets recorded in both places** —
  here in the step, and as an amendment row. Do not edit a decision row in place;
  the point is to see that it changed.

Status values: `not started` / `in progress` / `done` / `skipped` / `blocked`.

---

## House rules in force

Set 2026-09-25, applying to every step:

1. No comments in code, in any language.
2. `main.tf` module calls pass only the config object and other modules.
3. Root `locals` stay short; derivation happens inside each module.
4. No tests, assertions or validations in Terraform or Ansible — and no preflight
   playbook in the k3s path.

### Deviations these rules force on the plan

Recorded here so a later reader does not think they were oversights.

| Plan requirement | Status | Consequence |
| --- | --- | --- |
| Section 3 item 2 — preflight validating topology, routes, DNS, CIDR overlap, disk capacity, tool versions, image access | **Dropped** | The first thing to touch a node is the step 14 installer. Bad input surfaces mid-run. |
| Section 9 — "invalid/unreachable address combinations fail before deployment" | **Partially met** | Only to the extent the JSON schema can express it. Verified by hand in step 31 instead. |
| Section 9 — Terraform tests for schema/topology rejection | **Dropped** | No `.tftest.hcl` (house rule 4) and no CI validation job — a job would only ever see the committed examples, never the applied config. |
| Automated validation of the project configuration | **None** | Rejected 2026-09-25: the config lives outside the repo and is never committed, so pre-commit and CI would validate examples only. `project-config.schema.json` is a written contract plus a manual `uvx check-jsonschema` command. |
| CIDR overlap between `pod_cidr`, `service_cidr` and subnets | **Unenforced** | JSON Schema cannot express it and there is no automated schema check either. Operator responsibility, documented in `docs/k3s-deployment.md`. |
| Cloudflare DNS module preconditions (4 of them) | **Dropped in the rewrite** | Misconfiguration surfaces as a provider API error at apply. Conditions moved to `docs/dns.md`. |
| `docs/dns.md` claim that "Terraform refuses `proxied: true`" | **Corrected, not implemented** | Enforcement is the JSON schema via pre-commit and CI only. |

---

## Decision record

Filled in at **step 1**. Replace "Recommended" with your decision and the date.

| # | Question | Recommended | Decision | Date | Reasoning if different |
| --- | --- | --- | --- | --- | --- |
| R5 | `tags` vs `network_tags` for node roles | Use `network_tags: ["control-plane", "worker"]`; drop the `tags` concept | Confirmed as recommended | 2026-09-25 |  |
| R6 | `disk_type` for node disks | `balanced` (gp3), not `ssd` (io2 on AWS) | Confirmed — `balanced` | 2026-09-25 |  |
| R8 | `size_map` key for nodes | An existing capacity key, not a new `kubernetes` key | Confirmed — reuse `medium` | 2026-09-25 |  |
| R9 | Node size and accepted monthly cost | Start at `medium`; record the figure and raise budget alerts to match | **`small`** (2 vCPU / 2 GiB on GCP and AWS, 4 GiB on Azure); ≈ $95/month accepted | 2026-09-25 | Amended from `medium` the same day — see amendments |
| R3 | Availability-zone spread | Single zone now; 3-AZ as a separate follow-up with a `region_map` restructure | Single zone now; 3-AZ is a named follow-up | 2026-09-25 |  |
| R7 | Where SSH source CIDRs live | Cluster-level `admin_allowed_cidrs`; schema rejects per-VM `allowed_cidrs` in k3s mode | Confirmed as recommended | 2026-09-25 |  |
| R11 | Fate of `rabbitmq.certificate_days` | cert-manager `Certificate` duration in k3s mode; unchanged in Compose | Confirmed as recommended | 2026-09-25 |  |
| R14 | Break-glass access once the bastion is gone | Provider serial/console access **and** a documented CIDR-update apply that needs no cluster access | Console access **and** a documented CIDR-update apply | 2026-09-25 |  |
| R15 | Compose path lifetime | Supported until step 31 cutover passes, then removed under a named follow-up issue | Remove after step 31 cutover, under a named follow-up issue | 2026-09-25 |  |
| R16 | No CI deployment path | Accept as a written limitation; `helm diff` required in the runbook | Confirmed — `helm diff` required, not optional | 2026-09-25 |  |
| R4 | `network.management_subnet_cidr` with no bastion | Remove from the k3s branch, or document as reserved — not left silent | Confirmed — removed from the k3s branch | 2026-09-25 |  |
| R2 | ACME staging vs certificate-validating probes | Add a "staging tolerates untrusted TLS" switch rather than disabling the probe | Confirmed — staging-tolerates-untrusted-TLS switch | 2026-09-25 |  |
| T1 | RabbitMQ replica count | (not previously asked) | **One instance total**, not three | 2026-09-25 | Broker HA is not worth three replicas at this size; see the consequence note below |
| T2 | Redis replica count | (not previously asked) | One instance total | 2026-09-25 | Already the plan's baseline; now explicit |
| T3 | Workload placement | (not previously asked) | Application services distributed across the three nodes; **no full stack per node** | 2026-09-25 | Ordinary Deployments with topology spread, never DaemonSets |
| T4 | Node roles | (not previously asked) | All three nodes run the control plane and act as workers | 2026-09-25 | Confirms the plan; no control-plane taint |
| — | Preflight in the k3s path | Dropped (house rule 4) — confirm and record | Dropped | 2026-09-25 | |

**Recorded cost estimate (R9):** ≈ **$60**/month — 3 × `t3.small` ≈ $45, 3 × 60 GiB
gp3 ≈ $15, no NAT gateway, no load balancers; managed PostgreSQL excluded.

Against **≈ $65/month today**: 4 × `t3.micro` ≈ $30, disks ≈ $3, and a NAT gateway
≈ $32 that `routing.tf` creates unconditionally. The plan's R9 table omitted that
NAT gateway, so its "≈ $33 today" figure understated the current bill.

So the migration is roughly **cost-neutral**, not the 3–9× increase the review
finding described. `budgets.*.monthly_amount: 100` covers infrastructure plus an
economy managed PostgreSQL with room to spare; leave it at 100.

### Consequence of T1 that has to be carried forward

A single RabbitMQ instance means **the broker is a single point of failure**, in
the same way Redis already is. Publishing and consuming stop while that pod
reschedules. Quorum queues become pointless at one replica — they add cost and
give no failure tolerance, so the deployment uses ordinary durable queues on a
persistent volume instead.

The R3 single-zone decision helps here and is worth noticing: with all three
nodes in one zone, a zonal persistent disk **can** reattach when the broker pod
is rescheduled onto a different node. That property disappears the moment the
3-AZ follow-up lands, at which point single-instance stateful services need
revisiting. Write that into `docs/k3s-deployment.md` at step 30.

### Amendments

| Date | Which decision | Changed to | What forced the change |
| --- | --- | --- | --- |
| 2026-09-25 | R15 Compose path lifetime | **Compose is removed at step 3, not after the step 31 cutover.** | The schema accepts only the k3s layout, so no valid Compose configuration can exist. `deployment_target` is dropped with it — a field with one legal value. |
| 2026-09-27 | Ingress topology | **One entry node**, replacing round-robin DNS. `kubernetes.entry_node` names it; both hostnames publish one `A` record at its Elastic IP. | Operator decision. Simpler and cheaper than three records. Accepted cost: losing that node takes down the site and the API endpoint with no automatic failover, while the cluster stays healthy. |
| 2026-09-26 | AWS-only scope | **Hardened: no GCP or Azure edits at all**, including one-line shims to keep a plan running. | Offered a `try()` in `modules/azure/network/locals.tf:31` and it was declined. Consequence: `terraform plan` cannot complete until those clouds are done; see the verification note below. |
| 2026-09-26 | RDS subnet group | **Added `clouds.aws.rds_network.primary_subnet_cidr`**; the subnet group is now two private subnets. | Making the workload subnet public for the nodes had silently put the RDS subnet group in a public subnet. `publicly_accessible = false` still held, but the boundary was weaker than before. |
| 2026-09-25 | Cloud load balancers | **Removed entirely.** The step that provisioned them is deleted; `kubernetes.api_endpoint_mode` and `ingress.endpoint_mode` are gone from the schema. | Operator decision. Traefik runs as a DaemonSet on host ports 80/443; both hostnames publish three `A` records, one per node. Failover is client retry, not health checking. |
| 2026-09-25 | NAT gateway | **Removed**, as a consequence of public nodes. | `routing.tf` creates one today. With nodes public and the workload subnet routed to the internet gateway, it has no purpose. Saves ≈ $32/month plus per-GB processing. |
| 2026-09-25 | R9 cost estimate | **Corrected to ≈ $60/month**, against ≈ $65 today. | The plan's R9 table was wrong twice: it omitted the NAT gateway that exists today (understating the current bill by ≈ $32) and assumed two load balancers that no longer exist (overstating the new one by ≈ $35). The migration is close to cost-neutral. |
| 2026-09-25 | Implementation scope | **AWS only.** GCP and Azure are converted separately, by hand, later. | Operator decision at step 5. Caveat: all three trees are instantiated unconditionally in `main.tf`, so a non-AWS module that unconditionally reads a removed key still breaks an AWS plan. |
| 2026-09-25 | Per-VM `cloud` override | **Removed from `$defs/vm`.** | A k3s cluster with embedded etcd cannot span clouds, so the override could only produce a broken cluster. Safe to remove: every module reads it through `try()`. |
| 2026-09-25 | Per-VM secret grants | **Deleted.** Terraform creates secret containers but grants no identity read access. | The target design has the operator resolve secrets locally and write Kubernetes Secrets, so VM instance roles do not need access. Leaves an open question — see step 5 follow-ups. |
| 2026-09-25 | R9 node size | **`small`, not `medium`.** ≈ $95/month rather than ≈ $140. | Operator preference. Accepted risk: 2 GiB per node on GCP/AWS leaves ~1.1–1.4 GiB for pods after k3s overhead, which is tight under one-node loss. Flagged for measurement at step 31. |
| 2026-09-25 | Step 3 — `secret_mappings` location | **Moved off VMs to a top-level workload-keyed block.** | Found in step 4: `project-config.cloud-example.json` mapped `POSTGRES_PASSWORD` to *different* secret IDs per VM (`...history-db-password`, `...fetcher-db-password`). A flat cluster-level map would have collapsed two distinct database credentials into one. |
| 2026-09-25 | Cutover safety guard | **Separate Terraform state, not a config flag.** | `deployment_target` was the isolation mechanism. Without it, the only thing keeping the new cluster from destroying the running deployment is that they use different state files and different git revisions. |
| | | | |

---

## Cross-cutting notes

Things discovered during one step that matter to a later one. With no comments in
code and no assertions in the tree, this table and `docs/` are the only places an
invariant can live — use it freely.

| Discovered in | Affects | Note |
| --- | --- | --- |
| Step 3 | Step 15, 32 | CIDR overlap is unenforced anywhere. A `pod_cidr`/`service_cidr` collision surfaces as a half-working cluster. |
| Step 5 | All of Phase 2 | Each module defaults new config keys independently. Grep every new key across the three cloud trees before finishing Phase 2. |
| Step 1 (T1) | Steps 22, 30, 32 | One broker and one cache means messaging and sessions are interrupted whenever either pod reschedules. Client reconnection behaviour is load-bearing; monitoring is the only thing that will tell you it happened. |
| Step 1 (R3 × T1) | The 3-AZ follow-up | Single-zone is what makes single-instance stateful services tolerable — a zonal disk can reattach on another node in the same zone. Moving to 3 AZs breaks that and forces RabbitMQ, Redis and Postgres to be reconsidered. Not a drop-in change. |
| Step 1 (R9) | Step 32 | `budgets.*.monthly_amount` is 100; the estimate is ≈ $140. Raise it before the first full month. |
| Step 2 | Step 9 | `docs/dns.md` says Terraform "rejects a hostname that sits outside the zone". True today via a `lifecycle` precondition; step 8 deletes that precondition, so the sentence becomes false and must be corrected in the same commit. |
| Step 2 | Steps 3, 29, 32 | No automated config validation anywhere. Every schema constraint is advisory — it fires only when someone runs `uvx check-jsonschema` by hand. Do not design a later step around a bad config being unable to reach `terraform apply`. |
| Step 2 | Step 4 | `.gitignore` ignores `*.json` with per-file exceptions (`!project-config.example.json`, `!project-config.cloud-example.json`). A new `project-config.k3s-example.json` needs its own exception line or it silently will not be committed. |
| Step 3 | Steps 15, 32 | Three constraints are inexpressible in JSON Schema and have no second check: duplicate `internal_ip`, an `internal_ip` outside `workload_subnet_cidr`, and pod/service/subnet CIDR overlap. All three surface as a half-working cluster, not an error. |
| Step 3 | Step 28 | The root `allOf` rule for `managed_database: false` requires at least one VM with `role: "database"`. In-cluster PostgreSQL has no such VM, so that rule must be **deleted** or step 27 is unreachable. |
| Step 5 | Step 24 | No identity has read access to any secret any more. The per-VM grants were deleted and nothing replaced them. Decide the operator-read model before the resolution path is built. |
| Step 6 | Every Terraform step | `terraform plan` cannot complete at all until GCP and Azure are converted. Verify AWS work by `fmt` + `validate` being clean and no plan error naming a file under `modules/aws/` or the root. |
| Step 5 | Every Terraform step | `terraform validate` cannot catch config-attribute errors — the config is `jsondecode(file(...))`, resolved at plan. Always verify with a plan, using `-var project_config_path=...` or the Desktop default will be read instead. |
| Step 4 | Steps 24, 26, 29 | `secret_mappings` is now top-level and keyed by workload (`history`, `fetcher`, `ui`, `migration`), not per VM. The secrets modules and `outputs.tf`'s `workload_secret_access` both still read `vms[].secret_mappings` and will need rewriting. |
| Step 4 | Step 31 | `size_map` tiers differ by cloud: `small` is 2 GiB on GCP/AWS, 4 GiB on Azure. Unconfirmed against current Azure docs. Matters if `default_cloud` ever becomes azure. |
| Step 3 | Step 14 and everywhere | The schema accepts only the k3s layout, so there is no Compose config any module, plugin or output could ever receive. Delete Compose paths rather than branching them — a branch that cannot be reached is worse than none. |
| Step 3 | **Step 32 — destructive** | With `deployment_target` gone, nothing in the config separates old from new. Applying the new Terraform root against the **existing state** plans the destruction of every running workload host. Use a separate state/workspace; check the backend key before every cutover-window apply. |
| | | |

---

# Step entries

## Step 1 — Freeze the open decisions from the review findings

Status: `done` · Started: 2026-09-25 · Finished: 2026-09-25

**What was implemented**

- The decision table above, filled in and dated. Twelve review findings closed,
  plus four topology decisions (T1–T4) the findings did not anticipate.
- Consequence notes written for T1 (single broker) and for the R3/T1 interaction,
  and propagated into steps 22, 23, 27 and 32 of the step guide.

**Decisions made**

- Eight findings (R5, R6, R8, R7, R11, R4, R2, R16) confirmed as recommended.
- **R9:** `medium` nodes, ≈ $140/month accepted — roughly 4× today's ≈ $33.
- **R3:** single zone now; 3-AZ is a named follow-up.
- **R14:** provider console access plus a documented `admin_allowed_cidrs` apply.
- **R15:** Compose removed after the step 31 cutover.
- **T1:** one RabbitMQ instance, not three. Quorum queues dropped with it — at one
  replica they cost coordination and tolerate no failure.
- **T2:** one Redis instance (already the baseline; now explicit).
- **T3:** application services spread across the nodes; no full stack per node.
- **T4:** all three nodes run the control plane and act as workers.

**Problems faced**

- None in the step itself. Two things surfaced that are problems for later steps
  and are recorded in the cross-cutting notes rather than here.

**Left undone / follow-ups**

- `budgets.*.monthly_amount` is `100` in both example configs and the accepted
  estimate is ≈ $140. Raise it before step 31 or the first correct month alerts.
- 3-AZ spread, with the `region_map` restructure it needs. Blocked on nothing;
  deliberately deferred. It invalidates the zonal-disk reattachment that makes
  single-instance RabbitMQ and Redis tolerable, so it is not a drop-in change.
- Compose path removal, after step 31.

---

## Step 2 — Remove the false validation claims

Status: `done` · Started: 2026-09-25 · Finished: 2026-09-25

**What was implemented**

- Deleted all three comments from `modules/cloudflare/dns/main.tf`, including the
  one pointing at a `proxied` validation in `variables.tf` that does not exist.
- Rewrote the "Why the record is never proxied" section of `docs/dns.md` to say
  what is actually true: the schema pins `proxied` to `false`, nothing applies
  the schema automatically, and `proxied: true` reaches `terraform apply` intact.
  Added the manual `uvx check-jsonschema` command inline.

**Decisions made**

- **No pre-commit hook and no CI job for schema validation.** Tried, then
  rejected. The project configuration lives outside the repository and is never
  committed, so both would validate only the committed examples — a green check
  that never sees the applied file, which reads as coverage while proving
  nothing.
- The schema stays as a written contract plus an opt-in command run before
  applying.

**Problems faced**

- The original step assumed a pre-commit hook would protect the operator. It
  cannot: `.gitignore` ignores `*.json`, the real config is never staged, and
  hooks only ever receive staged files. This was found while checking the ignore
  rules, not while writing the hook — worth doing in that order next time.
- Knock-on: the step guide claimed in three places that the schema was "the only
  automated correctness check in the pipeline". All three were corrected, and
  step 28 now says explicitly not to reintroduce the job.

**Left undone / follow-ups**

- `docs/dns.md`'s zone-membership claim is still true but becomes false in step 8.
  Tracked in the cross-cutting notes.
- The TLS-ALPN-01 reasoning in `docs/dns.md` and in the schema's `proxied`
  description still has to be re-derived for HTTP-01 in step 8.

---

## Step 3 — Schema: replace the Compose layout with the k3s layout

Status: `done` · Started: 2026-09-25 · Finished: 2026-09-25

**What was implemented**

- `$defs/vm`: `role` pinned to `const: "kubernetes"`; all three `allOf` rules
  deleted (they were bastion/ui rules); `ssh_port`, `allowed_cidrs` and
  `public_endpoint` removed from `properties` so `additionalProperties: false`
  rejects them outright.
- `$defs/vm_network_tags`: enum replaced with `control-plane` / `worker`, and
  `minItems: 2` + `maxItems: 2` + `uniqueItems` so both are always present.
- `properties.vms`: bastion requirement dropped, `minProperties` and
  `maxProperties` both 3.
- `network.management_subnet_cidr` removed; `registry` replaced with the native
  shape (`repository_prefix`, `location`, `create`, and an `image_digests` map
  requiring a `sha256:` digest for fetcher, history, ui and migration);
  `host_vm` removed from `rabbitmq` and `redis`.
- Root `allOf`: the `managed_database` rule reduced to requiring
  `database_profile` and `database_profile_map` when true. Both VM-role clauses
  deleted.
- New required `kubernetes` and `ingress` objects.
- `$defs/image_digest` added. `memory_mb` on both services and
  `rabbitmq.certificate_days` now carry descriptions naming their Kubernetes
  meaning (R12, R11).

**Decisions made**

- **No `deployment_target` field.** With only one accepted layout it would have
  had one legal value. Consequence: the cutover guard is now Terraform state,
  not a config flag — recorded as an amendment and flagged in step 31.
- Registry shape is a proposal, not a derived requirement. Revisit in step 25
  when the publish workflows are written and the real digest plumbing is known.
- Constraints live directly in `$defs/vm` rather than in a `vms` branch, since
  every VM is a node now.

**Problems faced**

- None structural — deleting the Compose layout removed the
  conditionals-can-only-add-constraints problem entirely. The step took roughly
  a third of the effort the branch-based version would have.
- `minProperties`/`maxProperties` errors print the whole `vms` object before the
  reason. The path (`vms`) and the tail of the message are clear, but the output
  is noisy. Not worth working around.

**Verification**

Schema passes `Draft202012Validator.check_schema`. A hand-built k3s config
validates, and all thirteen rejection cases fail correctly: two nodes, four
nodes, non-`kubernetes` role, missing `worker` tag, per-VM `allowed_cidrs`,
per-VM `ssh_port`, an old network tag, `rabbitmq.host_vm`, per-VM
`public_endpoint`, `management_subnet_cidr`, an image tag instead of a digest,
an absent `kubernetes` block, and an invalid `api_endpoint_mode`.
`managed_database: false` is now accepted with no database VM, which unblocks
step 27, and `managed_database: true` still requires `database_profile`.

Confirmed inexpressible, as documented: duplicate `internal_ip` and pod/service
CIDR overlap are both accepted.

**Left undone / follow-ups**

- Both committed examples are now invalid (26 and 23 errors). Step 4 replaces
  them.
- The three inexpressible constraints need writing into `docs/k3s-deployment.md`
  at step 30; they exist only in this log until then.
- No validator is installed on this machine — no `uv`, `uvx`, `pre-commit`, and
  no `pip` in `.venv`. Verification used a throwaway venv with `jsonschema`.
  Install `uv` before step 4 or the manual schema command cannot be run.

---

## Step 4 — A committed k3s example config

Status: `done` · Started: 2026-09-25 · Finished: 2026-09-25

**What was implemented**

- Both examples converted in place, keeping what distinguishes them: GCP with
  `managed_database: false`, AWS with `true` plus `database_profile: "economy"`.
- Five/four VMs replaced by `k3s-1`, `k3s-2` and `k3s-3` — `size: "small"`,
  `disk_type: "balanced"`, 60 GiB, `assign_public_ip: true`, both network tags,
  `internal_ip` `.21`/`.22`/`.23` inside `workload_subnet_cidr` `10.0.1.0/24`.
- Removed `management_subnet_cidr`, both `host_vm` keys and the GHCR `registry`
  block. Added `kubernetes`, `ingress`, and the native registry shape.
- `ingress.hostname` and `ingress.acme_email` carry the values that were on the
  UI VM's `public_endpoint`; they moved rather than being invented.
- `GHCR_TOKEN` dropped from every secret mapping.

**Decisions made**

- **`small` rather than `medium`** — see the amendment. Cost estimate revised to
  ≈ $95/month.
- **`secret_mappings` moved out of the VM definitions** into a top-level
  workload-keyed block (`history`, `fetcher`, `ui`, `migration`), which required
  amending the step 3 schema.
- Registry `location` and `create` omitted from both examples so they
  demonstrate the defaults.
- `monitoring.synthetics.enabled` left `false` alongside
  `acme_environment: "staging"` — the R2 pairing, manual until step 12.

**Problems faced**

- The step as written said to set `secret_mappings: {}` on each node. That would
  have produced configurations from which Terraform creates **no secret
  containers at all**, since the secrets modules derive them from those maps.
  Caught by reading the existing values rather than by any check.
- Worse, `project-config.cloud-example.json` mapped `POSTGRES_PASSWORD` to two
  *different* secret IDs — `oilscope-dev-history-db-password` and
  `oilscope-dev-fetcher-db-password`. A flat cluster-level map keyed by
  environment variable name would have silently merged two distinct database
  credentials into one, losing the per-service separation the plan calls for in
  section 7. Hence the workload-keyed shape.

**Verification**

Both examples validate. New rejection cases confirmed: a per-VM
`secret_mappings`, an absent top-level `secret_mappings`, an unknown workload
key, a missing required workload, and a lowercase environment variable name.

**Left undone / follow-ups**

- `budgets.*.monthly_amount` left at `100`. Infrastructure fits; adding managed
  PostgreSQL puts the total near $110. Decide before step 31.
- The image digests are placeholders. Step 26 replaces them with real ones.
- `terraform plan` does not work and is not expected to until Phase 2 finishes —
  the modules still reference the `ui` and `bastion` roles and `host_vm`.
- The `size_map` tiers are not equivalent across clouds: `small` is 2 GiB on GCP
  and AWS but 4 GiB on Azure (`Standard_B2s`). Confirm the Azure row against
  current documentation before anyone switches `default_cloud` to azure, and
  record it in `docs/k3s-deployment.md` at step 30.

---

## Step 5 — Config plumbing, without growing the root

Status: `done` (AWS) · Started: 2026-09-25 · Finished: 2026-09-25

**What was implemented**

- `modules/aws/secrets/` rewritten: `all_secret_ids` now derives from the
  top-level workload-keyed `secret_mappings`, gated on
  `var.config.default_cloud == "aws"`. The per-VM `aws_iam_role_policy` grant and
  the `vms` variable are gone, so the `main.tf` call passes only `config`.
- `outputs.tf`'s `workload_secret_access` rewritten to read the new block, keyed
  by workload rather than by VM.
- Per-VM `cloud` removed from `$defs/vm`.
- `docs/k3s-deployment.md` created, holding the three unenforceable
  configuration rules, the defaulting convention, the cross-cloud size-tier
  mismatch, and the secrets model.
- `locals.tf` untouched, as intended.

**Decisions made**

- **AWS only from here.** Recorded as an amendment.
- Per-VM secret grants deleted rather than widened to all three nodes. Widening
  would have preserved a mechanism the plan explicitly moves away from.
- GCP and Azure secrets modules left untouched. They are inert with
  `default_cloud: "aws"` — their `vms` filter is empty, and an empty `for` never
  evaluates its body, so the stale `vm.secret_mappings` reads are never reached.

**Verification**

`terraform fmt -check -recursive` and `terraform validate` pass. A plan against
`project-config.cloud-example.json` no longer reports any `secret_mappings`
error, which was the step's target. It now fails on three things, all expected:
invalid AWS credentials on this machine, Azure credentials against the
placeholder subscription, and `modules/azure/network/locals.tf:31` reading the
`management_subnet_cidr` that step 3 removed.

**Problems faced**

- `terraform validate` cannot see any of this. The configuration arrives through
  `jsondecode(file(...))`, so attribute errors surface only at plan. Worth
  remembering for every remaining Terraform step.
- The root `project_config_path` variable defaults to
  `/Users/pavlo/Desktop/project-config.new.json`, so a plan reads that file
  unless `-var` overrides it. That real configuration also needs converting to
  the k3s layout, and nothing will tell you if it has not been.

**Left undone / follow-ups**

- **Nothing now grants read access to the secrets.** The VM grants are gone and
  no replacement exists. Settle this when step 21 builds the resolution path:
  either the operator's identity already has read access, or it needs an explicit
  grant.
- `modules/aws/network/main.tf:13` still reads `management_subnet_cidr` — step 6.
- GCP and Azure: `secrets/locals.tf` in both, `azure/network/locals.tf:31`,
  `gcp/network/network.tf:15`. Left for the separate per-cloud pass.

---

## Step 6 — Network modules: subnets and the firewall matrix

Status: `done` (AWS) · Started: 2026-09-26 · Finished: 2026-09-26

**What was implemented**

- Management subnet, NAT gateway and its EIP deleted. The workload subnet now
  associates with the public route table, so nodes reach the internet through the
  internet gateway.
- Five role security groups replaced by one `kubernetes` group: TCP 22 and 6443
  from `kubernetes.admin_allowed_cidrs`; TCP 6443, 2379, 2380, 10250 and UDP 8472
  `self`-only; TCP 80 and 443 from anywhere; egress open.
- `outputs.tf`: `management_subnet_id` removed, `security_group_ids` now
  `{ kubernetes = ... }`.
- `modules/aws/vm`: `management_subnet_id` dropped from the `network` variable
  type, and `subnet_ids` collapsed to the workload subnet.
- `modules/aws/database`: RDS ingress now from the node security group instead of
  the deleted `fetcher` and `history` groups.
- New private `rds_primary` subnet in the node availability zone, so the RDS
  subnet group is two private subnets rather than one public and one private.
- `resource_prefix`, `availability_zone` and `ui_public_ports` locals removed and
  computed where used.

**Verification**

Port matrix checked line by line against
<https://docs.k3s.io/installation/requirements> and matches: TCP 2379–2380
servers-to-servers, TCP 6443, TCP 10250, UDP 8472. The docs warn specifically
that 8472 must not be world-reachable; `self = true` satisfies that. UDP
51820/51821 are Flannel WireGuard only and TCP 5001 is only for the embedded
distributed registry (Spegel), so neither is opened.

`fmt -check` and `validate` clean. Both example configs validate, and a config
whose `rds_network` lacks `primary_subnet_cidr` is rejected. The plan reports no
error under `modules/aws/` or at the root.

**Problems faced**

- `outputs.tf` was missed on the first pass, and `try()` does not hide it: an
  undeclared *resource* is a static error, so `validate` failed with six
  diagnostics. Worth running `validate` before believing a module rewrite is
  finished.
- Deleting one output cascaded into two other modules, because
  `modules/aws/vm` declares `network` as a **typed object** with
  `management_subnet_id` required, and `modules/aws/database` indexed
  `security_group_ids` by the old role names. Keeping the map keyed by role is
  what kept `modules/aws/vm/locals.tf:45` working untouched.
- Making the workload subnet public quietly moved the RDS subnet group into a
  public subnet. Nothing failed, and nothing would have — it only widened what a
  single flag change could expose.

**Left undone / follow-ups**

- `aws_route_table.private` is created whenever AWS is enabled, but is only used
  when a managed database exists. Harmless, could be gated on `rds_enabled`.
- `modules/azure/network/locals.tf:31` still blocks any complete plan. Out of
  scope by decision.

---

## Step 7 — VM modules: the `kubernetes` role

Status: `done` (AWS) · Started: 2026-09-27 · Finished: 2026-09-27

**What was implemented**

- `locals.tf` reduced to a single `aws_vms`, gated on
  `default_cloud == "aws"`. The `vm_clouds` indirection went with the per-VM
  `cloud` key; `resource_prefix`, `common_labels`, `vm_labels`, `subnet_ids`,
  `security_group_ids` and `cloud_init_user_data` are all computed where used.
- **One shared IAM role and instance profile** for all three nodes, replacing
  one per VM. Step 9 attaches ECR pull permissions to it once.
- `network_tags` now become EC2 tags, `<name_prefix>-<tag> = "true"` — so
  `oilscope-control-plane` and `oilscope-worker`. This is what step 13's
  inventory plugin groups on.
- Dead `role != "bastion"` removed from detailed monitoring.
- `monitoring.tf`: the per-VM policy became one policy on the shared role, and
  the Traefik log-group grant is no longer gated on `role == "ui"` — Traefik is
  a DaemonSet on every node now, so every node needs it.
- `vms` output dropped `role_arn` and `role_name` (nothing consumed them once
  the secrets grants went). Added module-level `node_role_name` / `node_role_arn`
  for step 9.

**Decisions made**

- **No `map_public_ip_on_launch`.** Existing behaviour kept: the EIP attaches
  after the instance exists, so a node has no route out during first boot.
  Network-dependent setup happens in Ansible after the EIP is attached. Today's
  `user_data` only writes SSH users, so nothing depends on boot-time egress.
- Consumers were checked before trimming the `vms` output: `aws_monitoring`
  needs only `instance_id`, `cloudflare_dns` only `public_ip`.

**Verification**

`fmt -check` and `validate` clean. No `bastion`, `ui`, `history`, `fetcher` or
`vm.cloud` reference remains anywhere under `modules/aws/vm/`. The plan reports
no error under `modules/aws/` or at the root.

**Problems faced**

- `monitoring.tf` inside this module was role-driven in a way the step
  description had missed: it gated the Traefik log-group grant on
  `role == "ui"`. With every node `kubernetes` that branch went dead silently —
  no error, just a permission that stops being granted. Worth remembering that
  `role ==` comparisons fail quietly where `role !=` ones usually do not.

**Left undone / follow-ups**

- `modules/aws/monitoring/` has the same shape — `ui_vms`, and an `agent.tf`
  lookup keyed by `ui`/`history`/`fetcher`/`database`. Step 12.
- Still no way to verify against a real plan: AWS STS rejects from this machine,
  so no AWS resource is ever planned here.

---

## Step 8 — Point both hostnames at the entry node

Status: `done` · Started: 2026-09-27 · Finished: 2026-09-27

**What was implemented**

- `kubernetes.entry_node` added to the schema (required, after `version`) and set
  to `k3s-1` in all three configs.
- `modules/cloudflare/dns/main.tf` rewritten, 75 lines to 24, no locals: one
  `for_each` over `{ ingress, api }` producing two `A` records, both pointing at
  `var.vm.vms[entry_node].public_ip`.
- Deleted from that module: `ui_vm_keys`, `one()`, the three-cloud `public_ips`
  map, the `hostname` and `ip_address` locals, all four `lifecycle` preconditions
  and all three comments.
- Interface replaced: `config` now declares `ingress` and `kubernetes` instead of
  `vms` and `default_cloud`; the three `*_vms` map arguments became one
  `vm = module.aws_vm`, typed `any` to match every other module.
- `summary` moved to its own `outputs.tf` and became a map keyed by record
  purpose, carrying `entry_node`.
- Root `main.tf` also lost the leftover `vms = module.aws_vm.vms` on
  `aws_secrets`, missed in step 5.
- `docs/dns.md` reasoning re-derived for HTTP-01 and the entry node.

**Decisions made**

- `for_each` keyed by record purpose (`ingress` / `api`), not by address. Keying by
  IP would make an Elastic IP change a destroy-and-recreate on a live ingress
  name rather than an in-place update.
- `type = any` on the `vm` input. Consistent with the rest of the repo, at the
  cost of no shape checking at the module boundary.

**Verification**

All three configs validate. A config missing `entry_node` is rejected; one whose
`entry_node` names a VM that does not exist is **accepted** — the fourth
unenforceable rule. `fmt -check` and `validate` clean, 56 AWS resources plan
unchanged.

The two Cloudflare records themselves could not be planned here:
`CLOUDFLARE_API_TOKEN` is not in this shell, so the zone data source fails first.
Still unverified — a plan from the operator's side should show exactly two
`cloudflare_dns_record.entry` resources with `proxied = false` and `content` equal
to `k3s-1`'s Elastic IP.

**Problems faced**

- I had claimed repeatedly, in this document and the step guide, that `one()` on
  an empty list raises an error. It does not — it returns `null`, confirmed with
  `terraform console`. The module's real failure was the first `lifecycle`
  precondition, with a readable message. The work was unchanged but the urgency
  was overstated; both documents are corrected.
- Whole-file rewrites were done with heredocs, which display nothing, and then
  summarised in prose. Corrected on request and recorded as a standing
  preference: always show the diff.

**Left undone / follow-ups**

- `docs/dns.md` still mentions CI running `terraform test`, which step 28 removes.
- Traefik DaemonSet-versus-pinned is still open and belongs to step 19. It decides
  whether entry-node recovery is one step or three.

---

## Step 9 — Cloud-native container registry

Status: `done` · Started: 2026-09-27 · Finished: 2026-09-27

**What was implemented**

- New `modules/aws/registry/`: four ECR repositories named
  `<repository_prefix>/<image>`, a lifecycle policy per repository, a GitHub
  OIDC provider, a publisher role and policy, and a pull-only policy attached to
  the shared node role from step 7.
- Schema: `registry.location` removed (ECR is always in the provider region, so
  it had no consumer); `image_digests.migration` renamed to `database` to match
  `Dockerfile.database`; `github_repository` and `publish_tag_prefix` added, tied
  together with `dependentRequired`.
- Root `main.tf` wires `aws_registry` with `config` and `vm = module.aws_vm`;
  root outputs gain `registry` and `registry_publisher_role_arn`.
- New `.github/workflows/publish-pavlo.yaml`: triggers on `pavlo-v*` tags,
  assumes the publisher role by OIDC, builds the four images and pushes to ECR,
  then writes each digest into the job summary ready to paste into
  `registry.image_digests`.

**Decisions made**

- **Lifecycle: untagged expire after 1 day, keep the five most recent.** Old
  images are explicitly not wanted, so no attempt to protect a rollback digest.
  Consequence: six pushes without a redeploy delete the digest the running
  deployment references. Cached images keep existing pods alive; a fresh node
  could not pull.
- **`image_tag_mutability = "MUTABLE"`.** IMMUTABLE is safer but breaks
  re-pushing a moved tag. Deployment is by digest, so tag mutability does not
  affect deployment safety.
- **OIDC trust scoped to `refs/tags/<publish_tag_prefix>*` only.** An earlier
  draft allowed `refs/heads/*` and `refs/tags/*`; `repo:X:*` would also have
  matched `pull_request` subjects, which fork PRs receive.
- **The tag prefix lives in config, not the module**, so other participants can
  point their own prefix at their own account with no Terraform change.
- The new workflow does not reuse `reusable-build-image.yaml`: that one logs into
  ghcr.io with `GITHUB_TOKEN` and has no `id-token` permission.

**Verification**

`fmt -check`, `validate` and `yamllint` clean. All three configs validate.
`github_repository` without `publish_tag_prefix` is rejected; neither field is
accepted, keeping local-only publishing valid. 68 AWS resources plan, 12 of them
registry. `aws iam list-open-id-connect-providers` is empty, so creating the
provider will not collide.

The rendered trust policy could not be inspected: `assume_role_policy` is
`(known after apply)` because it references the provider ARN. Read it once after
the first apply.

**Left undone / follow-ups**

- `registry.image_digests` are all `sha256:0000…` placeholders until the first
  tag push.
- `pavlo-v*` names a destination, not a person — anyone able to push a matching
  tag can publish to this account. Closing that needs GitHub tag protection or an
  Environment with reviewers, both repository-settings changes. Recorded in the
  schema description.
- Step 25 still has to retire the GHCR path and reconcile the two workflows.

---

## Step 10 — Decouple the database modules from VM roles

Status: `not started` · Started: ____-__-__ · Finished: ____-__-__

**What was implemented**

-

**Decisions made**

-

**Problems faced**

-

**Left undone / follow-ups**

-

---

## Step 11 — Cluster outputs

Status: `not started` · Started: ____-__-__ · Finished: ____-__-__

**What was implemented**

-

**Decisions made**

-

**Problems faced**

-

**Left undone / follow-ups**

-

---

## Step 12 — Monitoring: stop the staging canary from alarming

Status: `not started` · Started: ____-__-__ · Finished: ____-__-__

**What was implemented**

-

**Decisions made**

-

**Problems faced**

-

**Left undone / follow-ups**

-

---

## Step 13 — Direct-SSH inventory

Status: `done` (AWS) · Started: 2026-09-27 · Finished: 2026-09-27

**What was implemented**

- `oilscope_aws.py` groups on the EC2 tags step 7 writes:
  `k3s_servers` from `<name_prefix>-control-plane`, `k3s_workers` from
  `<name_prefix>-worker`. Both hold all three hosts.
- `ansible_host` is now the public address for every node; the
  `is_bastion ? public : private` expression and the `bastion_ssh_port`
  composed variable are gone, as is the `bastion_role` plugin option.
- New `apply_direct_connection_vars` in `module_utils`, used only by the AWS
  plugin: no ProxyCommand, and `OILSCOPE_SSH_KEY` required rather than
  defaulted.
- `DOCUMENTATION` rewritten for the new topology; it now declares two options
  instead of three.

**Decisions made**

- **The bastion helpers stay in `module_utils`.** The step said to delete
  `bastion_ssh_port`, `bastion_connect_port` and `_proxy_command_args`, but
  `oilscope_gcp.py` and `oilscope_azure.py` both import them. Deleting would
  break two plugins reserved for the operator's own pass. A parallel function
  was added instead; the old path goes when those clouds are converted.
- **`OILSCOPE_SSH_KEY` is required on AWS.** The shared
  `ssh_private_key_file()` falls back to `~/.ssh/google_compute_engine`, which
  no AWS instance carries — its own docstring called the variable "effectively
  required" here. The fallback only turned a missing setting into three
  permission-denied failures. The shared helper is untouched, since GCP
  legitimately uses that default.
- `validate_inventory_hosts` kept. The role comparison is now a tautology, but
  the same function catches a `name_prefix`/`environment` mismatch and a
  partial discovery — and a partial discovery here would silently build a
  two-node etcd cluster.

**Problems faced**

- The `DOCUMENTATION` block is parsed as YAML, so a `: ` inside an unquoted
  scalar breaks plugin loading. Two added sentences used colons and had to be
  rewritten with dashes — which is why the rest of the file avoids colons.
  Caught by parsing the docstring directly, not by `py_compile`.

**Verification**

`py_compile` on both files; `DOCUMENTATION` and `EXAMPLES` parse as YAML and
declare the expected options; the GCP and Azure plugins still resolve their
imports from `module_utils`.

**Not verifiable yet.** `ansible-inventory --list` needs running instances and
nothing is applied. First real exercise is after step 15, so a mistake here
surfaces as "Ansible cannot reach the nodes" mid-bootstrap.

**Left undone / follow-ups**

- `OILSCOPE_SSH_KEY` is not set in the operator's shell. The inventory fails
  with the new message until it is.
- `inventory/oilscope-aws.yml` still carries no `project_config_path`, so it
  falls back to the option default `../../terraform/env/dev.json`, which does
  not exist. Set `OILSCOPE_PROJECT_CONFIG` or add the key before first use.

---

## Step 14 — Install k3s and form the cluster

Status: `written, unverified` · Started: 2026-09-27 · Finished: 2026-09-27

**What was implemented**

- `playbooks/bootstrap_k3s.yml`: four plays over `k3s_servers` —
  `host_baseline` on all three, `--cluster-init` on the entry node only, read
  the token, then `serial: 1` joins over the private bootstrap address.
- `roles/k3s_server/` with `meta`, `defaults`, `tasks` and a `config.yaml.j2`
  template writing `node-ip`, `advertise-address`, the pod and service CIDRs,
  `secrets-encryption`, `disable: [traefik, servicelb]` and the TLS SAN list.
- Version pinned from `kubernetes.version` through `INSTALL_K3S_VERSION`.
- `docker_engine` deliberately not used: k3s ships containerd, and a second
  runtime competes for the same images and cgroups.
- `docs/k3s-deployment.md` gained a **Cluster bootstrap** section holding the
  reasoning that cannot live in comments.

**Decisions made**

- **Two independent guards against a second `--cluster-init`**: `creates:` on
  the k3s binary, and a `stat` of the etcd datastore directory. A second
  cluster-init does not fail — it builds a fresh single-member etcd and orphans
  the data — so this is the one place worth belt and braces rather than one
  check.
- The worker label is applied with `kubectl label` after the node is Ready,
  not through `node-label`.
- Token passed between plays as a fact with `no_log`, and the entry node's
  inventory hostname derived from `name_prefix`/`environment`/`entry_node`
  rather than searched for.

**Problems faced**

- **First version would have failed on all three nodes.** The template set
  `node-role.kubernetes.io/control-plane` and `worker` through `node-label`. The
  kubelet is forbidden from assigning itself labels in that prefix, so k3s
  refuses to start. k3s applies `control-plane`, `master` and `etcd` itself;
  `worker` is not one of them and needs the API. Only `oilscope.io/entry-node`
  goes through `node-label`.
- A comment explaining that was written into the role and rejected on review —
  correctly, house rule 1. It moved to `docs/k3s-deployment.md`.
- The first token lookup selected whichever host had the fact defined, which
  obscured the intent. Replaced with the derived entry hostname.

**Verification**

`yamllint` clean. `ansible-lint` passes at the **production** profile across 11
files. No comments in either new file.

**Unverified, and more than usual.** Lint proves parsing, not behaviour. Still
untested: whether the etcd-membership wait works (it polls the
`node-role.kubernetes.io/etcd` label, believed to be set by k3s on embedded-etcd
servers but not observed); whether `ansible_facts.hostname` matches the k3s node
name; the idempotency claim, which is the entire point of the re-init guard; and
`changed_when: "'not labeled' not in stdout"`, which depends on kubectl's exact
wording. All need a disposable cluster.

**Left undone / follow-ups**

- `OILSCOPE_SSH_KEY` unset in the operator's shell — the inventory fails first.
- `inventory/oilscope-aws.yml` carries no `project_config_path`, so it falls
  back to a default path that does not exist.
- The token is generated here but nothing backs it up yet. A snapshot without
  the token is not a backup — step 16.

---

## Step 15 — Local kubeconfig

Status: `written, unverified` · Started: 2026-09-27 · Finished: 2026-09-27

**What was implemented**

- `roles/k3s_kubeconfig/` slurps `/etc/rancher/k3s/k3s.yaml` from the entry node
  with `no_log`, rebuilds the document, and writes it through
  `delegate_to: localhost` at mode `0600`.
- Added as the final play of `bootstrap_k3s.yml`, so a bootstrap ends with a
  usable kubeconfig.
- `.gitignore` gained `*.kubeconfig`, `kubeconfig`, `.kubeconfig/` and
  `**/kube/*.yaml`.
- `docs/k3s-deployment.md` gained a **The kubeconfig** section including
  rotation.

**Decisions made**

- **The file goes to `~/.kube/<name_prefix>-<environment>.yaml`, not into the
  repository.** This reverses the recommendation made when explaining the step.
  A cluster-admin credential in a working tree is one `git add -f` from
  disaster, and playbooks reference it by variable either way. The gitignore
  rules stay as a net for anyone who overrides the path inward.
- **The document is rebuilt, not patched.** A `regex_replace` on `127.0.0.1`
  would have been shorter but would have left k3s's `default` names for cluster,
  user and context, which collide with every other k3s kubeconfig. They are now
  `<name_prefix>-<environment>`.
- `certificate-authority-data` carried across unchanged. The hostname changed,
  the trust did not; `insecure-skip-tls-verify` is never substituted.
- Never merged into `~/.kube/config` and `KUBECONFIG` never exported, so a stray
  `kubectl config use-context` cannot point a later `helm upgrade` at the wrong
  cluster.

**Verification**

`yamllint` clean, `ansible-lint` production profile across 13 files. The
gitignore rules were checked with `git check-ignore` rather than assumed —
`.kubeconfig/oilscope.yaml`, `infrastructure/ansible/kube/oilscope.yaml`,
`oilscope.kubeconfig` and `kubeconfig` all match.

Worth recording why that check mattered: **neither `gitleaks` nor
`detect-private-key` catches a kubeconfig**, because the key is base64 inside
YAML rather than a PEM block. The gitignore rule is the only thing standing
there.

**Unverified.** Needs a cluster: the `from_yaml` and index-`[0]` assumption
about k3s's file shape, and whether `to_nice_yaml` output is accepted by kubectl
without complaint.

**Left undone / follow-ups**

- The admin certificate is long-lived with no revocation list; containing a leak
  means rotating the cluster CA. Documented, not mitigated.

---

## Step 16 — etcd snapshots, off-node backup, and recovery

Status: `skipped` · Deferred 2026-09-27

**Decision.** Not implemented for now; may be picked up later. Nothing was
written. The step guide keeps the full specification.

**What the step would have needed, recorded so it does not have to be
rediscovered**

- A Terraform half the guide omitted: an S3 bucket (versioned, encrypted,
  public access blocked) plus `PutObject`/`GetObject`/`ListBucket`/`DeleteObject`
  on the step 7 node role, since k3s prunes its own snapshots. The bucket name
  derives as `<name_prefix>-<environment>-etcd-snapshots` and travels through the
  existing `terraform_outputs_path` pattern — no new config field.
- Ansible would mostly be additions to `config.yaml.j2`: k3s has native
  `--etcd-snapshot-schedule-cron`, `--etcd-snapshot-retention`, `--etcd-s3`,
  `--etcd-s3-bucket`, `--etcd-s3-folder`, `--etcd-s3-region`. Scheduling,
  retention, upload and pruning are all built in — no cron job, no upload script.
- **Open question never resolved:** the documented S3 configuration takes an
  access key and secret key. The nodes have an IAM instance role, and static keys
  on three nodes would undo what step 9 established. Whether k3s falls back to
  the instance profile when the keys are empty needs checking before building on
  the native path.
- **Gotcha from the k3s docs:** the S3 config Secret cannot be used for restore.
  A restore must be given the bucket details as flags or environment — which
  matters because restore is exactly when the cluster may not be serving Secrets.
- R13: `0 */6 * * *` fires on all three servers at once, so the cron needs
  offsetting per node.
- Recovery deliberately performs the destructive operation step 14 guards
  against (`--cluster-reset`), which is why it belongs in a separate, explicitly
  invoked playbook.

**What skipping actually costs**

Less than it appears. The cluster is reproducible from Terraform, Ansible and
Helm, so losing etcd does not lose the deployment — it loses an afternoon. Going
through what etcd actually holds:

| At risk | Real exposure |
| --- | --- |
| Application data | **None from this.** RDS has its own automated backups, per `backup_retention_days` in the database profile. |
| RabbitMQ messages, Redis sessions | **Not covered by etcd snapshots anyway** — they live on PVCs. Sessions are transient by design. |
| Secrets, Ingresses, ConfigMaps | Re-created by re-running the deployment. |
| cert-manager account key and issued certificates | **The genuine exposure.** Re-issuing runs into Let's Encrypt rate limits — five duplicate certificates per week. A rebuild during a bad week could leave the site without a trusted certificate. |

So the honest summary is that etcd snapshots protect less in this design than the
plan implies, which makes deferring defensible.

**Live consequences to carry forward**

- **The k3s token is backed up nowhere.** It stays retrievable from
  `/var/lib/rancher/k3s/server/token` as long as one node survives, and it is
  needed to join any future server. Losing all three nodes at once loses it.
- **Step 31 cannot perform its restore checks** — "etcd restore and
  stateful-service restore both work from off-node backups". That line is now
  untestable and should be marked as such rather than quietly passed.
- Step 22's note that the RabbitMQ volume is the only copy of undelivered
  messages still stands, and now has no backup path at all.
- `docs/k3s-recovery.md`, listed for step 30, will not exist.

---

## Step 17 — Helm scaffolding and pinned versions

Status: `done` · Started: 2026-09-27 · Finished: 2026-09-27

**What was implemented**

- `infrastructure/helm/versions.yml`: a new top-level directory with `upstream`,
  `owned` and `application` sections, the three verified tool versions, and
  `verified_on: "2026-09-27"` so a reader can tell how stale the pins are.
- `playbooks/deploy_k3s.yml`: the Helm execution contract — `hosts: localhost`,
  `connection: local`, `become: false`, kubeconfig derived from the project
  configuration and required to exist before anything runs.
- `requirements.yml` declares `kubernetes.core >=6.0.0`; `requirements.txt` adds
  `kubernetes` and `PyYAML`.
- `docs/k3s-deployment.md` gained a **Helm from the operator's machine** section
  with the local setup, the `helm diff` plugin install and the Bitnami evidence.

**Pins, each queried with `helm show chart` against the live repository**

| Purpose | Chart | Chart version | App version |
| --- | --- | --- | --- |
| Storage | `aws-ebs-csi-driver` | 2.66.0 | 1.66.0 |
| Ingress | `traefik` | 41.6.0 | v3.7.13 |
| Certificates | `cert-manager` (OCI, quay.io/jetstack) | v1.21.2 | v1.21.2 |

**The finding that settles steps 21 and 22**

The plan's warning about image availability was justified. Checked against the
Docker Hub registry API:

| Reference | Result |
| --- | --- |
| `bitnami/rabbitmq:4.1.3-debian-12-r1` — the Bitnami chart's **own default** | **HTTP 404** |
| `bitnami/redis:latest` — the Bitnami chart's **own default** | 200, floating tag |
| `bitnamilegacy/rabbitmq:4.1.3-debian-12-r1` | 200 |

The Bitnami charts install cleanly and then fail to pull their own images: the
versioned images moved to `bitnamilegacy`, which is frozen and unsupported, and
the Redis chart defaults to a tag this project does not deploy.

**Decision:** repository-owned charts wrapping the official upstream images the
project already pins for Compose — `rabbitmq:4.2.9-management` and
`redis:8.6.6`, both verified pullable, plus `postgres:18.6-bookworm` for step 27.
One set of version pins instead of two.

**Problems faced**

- `ansible-lint` failed with `couldn't resolve module 'kubernetes.core.helm_info'`
  — an environment artifact, not a code error. `ansible-lint` runs its own
  `ansible-core 2.21.0` and searches `~/.ansible/collections`, while
  `kubernetes.core 6.5.0` lives inside the Homebrew ansible install. Verified by
  pointing `ANSIBLE_COLLECTIONS_PATH` at it rather than installing anything. CI
  is unaffected: its lint step installs from `requirements.yml`, which now
  declares the collection.

**Verification**

`yamllint` clean; `ansible-lint` production profile once the collection path is
correct. Nothing installed to a cluster — there is no cluster.

**Left undone / follow-ups**

- **`helm diff` is not installed.** It is a Helm plugin, so `requirements.yml`
  cannot pin it, and the R16 decision made it required rather than optional.
  Without it steps 19 onward proceed with no drift visibility.
- kubectl 1.35 against a k3s 1.36 server is one minor behind, which Kubernetes
  supports. It stops being fine after another k3s bump.

---

## Step 18 — Cloud CSI storage

Status: `written, unverified` · Started: 2026-09-27 · Finished: 2026-09-27

**What was implemented**

- `infrastructure/helm/values/aws-ebs-csi-driver.yaml`: two controller replicas,
  and the `oilscope-gp3` StorageClass created by the chart's own
  `storageClasses:` list rather than a separate manifest — gp3, encrypted,
  expandable, `WaitForFirstConsumer`, `reclaimPolicy: Retain`, marked default.
- `local-storage` added to the k3s `disable` list in step 14's template.
- `AmazonEBSCSIDriverPolicy` attached to the node role in `modules/aws/vm`,
  with the ARN built from `data.aws_partition` rather than hardcoded `arn:aws:`.
- Helm install and a storage-class report added to `deploy_k3s.yml`.

**Decisions made**

- **`local-storage` disabled rather than leaving two classes.** k3s marks
  `local-path` the default, so any PVC that does not name a class silently gets
  node-local disk — RabbitMQ's volume would live on one node's filesystem and
  come up empty if the pod moved. No error, just an empty broker. Disabling
  removes the wrong option instead of managing an annotation.
- **`reclaimPolicy: Retain`.** With step 16 deferred, a retained disk after a
  PVC delete is the closest thing to a safety net this deployment has.
- **The driver authenticates as the node, not via IRSA.** There is no OIDC
  provider for the cluster — step 9's is for GitHub Actions — and registering k3s
  with AWS as an identity provider is separate work. Accepted tradeoff: every pod
  on the node inherits EBS permissions through IMDS, which network policy cannot
  prevent because IMDS is link-local. Written up in `docs/k3s-deployment.md`
  rather than left unnoticed.
- The AWS-managed policy is preferred to a hand-written statement list, since AWS
  maintains it as the driver's needs change.

**Verification**

`yamllint`, `terraform fmt -check`, `terraform validate` and `ansible-lint`
(production profile) all clean. The plan shows
`aws_iam_role_policy_attachment.node_ebs_csi[0]`; AWS resources 73 to 74.

**Unverified.** Needs a cluster: that the chart's `storageClasses:` list produces
what is expected, that a PVC binds and a pod mounts it, that expansion works, and
that exactly one default class exists once `local-storage` is gone.

**Left undone / follow-ups**

- The `local-storage` change only takes effect on a k3s restart. The role's
  configuration-change handler covers a re-run against an existing cluster.
- IMDS credential exposure to all pods, as above.

---

## Step 19 — Traefik

Status: `done` (rendered, not deployed) · Started: 2026-09-27 · Finished: 2026-09-27

**What was implemented**

- `infrastructure/helm/values/traefik.yaml`: DaemonSet, host ports 80 and 443,
  `service.enabled: false`, ingress class `oilscope` and not default, port 80
  redirecting permanently to 443 at the entrypoint, JSON access logs, and
  resource requests and limits.
- Install and a ready-vs-desired report added to `deploy_k3s.yml`.
- `docs/k3s-deployment.md` gained an **Ingress** section.

**Decisions made**

- **DaemonSet rather than pinned to the entry node**, as recommended when the
  entry-node design was agreed. Costs three pods (~300 MiB of a ~1.2 GiB budget
  on 2 GiB nodes) and buys a failover that is a DNS change and nothing else.
- **No Service object at all.** There is no load balancer to front one and
  ServiceLB is disabled, so a ClusterIP Service for the ingress controller would
  be an unused object. Host ports are the entire ingress path.
- **Not the default ingress class.** Every Ingress names `oilscope` explicitly,
  so nothing is silently adopted if a second controller ever appears.
- **The 80 to 443 redirect is on the entrypoint, not a router middleware.**
  Traefik exempts the ACME HTTP-01 solver from an entrypoint redirect; a
  middleware-level one would break issuance with no obvious cause. This matters
  for step 20.

**Problems faced**

- The first values file failed the chart's own JSON schema in four places:
  `ports.web.redirectTo`, `ports.websecure.tls`, a top-level `logs:` block, and
  `log.general`. The real keys in chart 41.6.0 are
  `ports.web.http.redirections.entryPoint`, `ports.websecure.http.tls`, and
  separate top-level `log:` and `accessLog:`. All four would have looked
  plausible and failed at install time — caught only by rendering.

**Verification**

`helm template` against chart 41.6.0 exits 0 and produces exactly what was
intended: one DaemonSet, one IngressClass named `oilscope` with
`is-default-class: "false"`, `hostPort: 80` and `hostPort: 443` on the container,
and **zero** Service objects. `yamllint` and `ansible-lint` production profile
clean.

This is the first Phase 4 step verified by more than linting — `helm template`
needs no cluster.

**Left undone / follow-ups**

- Still unproven on a cluster: that host ports actually bind (nothing else should
  hold 80/443, but nothing checks), and that the DaemonSet schedules on all three
  nodes given there are no taints to tolerate.

---

## Step 20 — cert-manager, ClusterIssuer, and the internal CA

Status: `written, unverified` · Started: 2026-09-27 · Finished: 2026-09-27

**What was implemented**

- `infrastructure/helm/values/cert-manager.yaml`: `crds.enabled: true`,
  `crds.keep: true`, one replica each for controller, webhook and cainjector with
  requests and limits, `startupapicheck` enabled with a 5m timeout.
- `roles/k3s_certificates/` installing the chart, waiting for the webhook, then
  applying four objects from `templates/issuers.yaml.j2` and waiting for the
  internal CA to reach `Ready=True`.
- Wired into `deploy_k3s.yml` through `include_role` in task position.

**Decisions made**

- **The ACME directory is a literal in the template**, not a variable or a role
  default. A default would still have been a knob overridable from a playbook or
  `-e`; switching to staging is now a code change, which is the intent.
- **CA lifetime is `certificate_days × 10`** — 87600h, about ten years, renewing
  a year early. A CA must outlive the leaf certificates it signs. The multiplier
  is a role default because it is a lifetime ratio, not an environment.
- **R11 applied**: `rabbitmq.certificate_days` drives the internal CA duration.
- **The webhook race is handled twice** — `startupapicheck` in the chart, plus an
  explicit wait on `cert-manager-webhook` Endpoints having subsets. The failure
  mode is `failed calling webhook … connection refused`, which names nothing
  useful, so belt and braces was worth it.
- `crds.keep: true` left at the chart default. Deleting cert-manager's CRDs would
  delete every `Certificate` and `Issuer`, and Kubernetes would garbage-collect
  the certificate Secrets. With step 16 deferred, that is the difference between
  an inconvenience and re-issuing everything against the weekly rate limit.

**Problems faced**

- **A real ordering bug the linter surfaced.** The first version added the role in
  a `roles:` section of the play that also has `tasks:`. Ansible runs `roles:`
  **before** `tasks:`, so it would have executed before `k3s_kubeconfig` was set.
  `ansible-lint` reported it as an unresolvable role, which was pointing at the
  ordering problem underneath. Switched to `ansible.builtin.include_role`.
- The first draft put the ACME directory in `defaults/main.yml` and was rejected
  on review: a default is still a way to choose an environment.

**Verification**

`helm template` of cert-manager v1.21.2 exits 0 and renders all six CRDs. The
issuer template renders to valid YAML with the four expected objects: ClusterIssuer
`letsencrypt` against the production directory with an HTTP-01 solver on ingress
class `oilscope`, ClusterIssuer `oilscope-selfsigned`, the CA Certificate at
87600h duration and 8760h renewBefore, and ClusterIssuer `oilscope-internal-ca`.
`yamllint` and `ansible-lint` production profile clean.

**Left undone / follow-ups**

- Unverified on a cluster: whether the webhook Endpoints wait is sufficient, and
  whether HTTP-01 actually completes — which needs the Cloudflare records applied,
  `proxied` false, and the entry node reachable on port 80.
- The ACME account key Secret (`letsencrypt-account-key`) has no backup, and with
  step 16 deferred nothing will give it one. Losing it re-registers the account
  and resets rate-limit accounting.

---

## Step 21 — Secrets into the namespace

Status: `written, unverified` · Started: 2026-09-27 · Finished: 2026-09-27

**Reordered.** This was step 23. RabbitMQ and Redis both need credentials in the
namespace before they can start, so secrets moved ahead of them and the three
rotated: secrets 21, RabbitMQ 22, Redis 23. Six cross-references in the two
documents were corrected, including a "Symmetry with step 21" note that would
otherwise have pointed at itself.

**What was implemented**

- `roles/k3s_secrets/` running on `localhost`: creates the namespace, reads each
  value from AWS Secrets Manager with the operator's own identity through the
  `amazon.aws.secretsmanager_secret` lookup, and mirrors them into
  namespace-scoped Kubernetes Secrets. `no_log: true` on both the resolution and
  the write.
- One Secret per workload, keyed by environment variable name, so step 26's
  Deployments can use `envFrom.secretRef` rather than enumerating keys.
- Wired into `deploy_k3s.yml` ahead of cert-manager.

**Decisions made**

- **One Secret per workload rather than one per value.** The mapping is already
  workload-keyed in the configuration, and `envFrom` is simpler than listing
  every key in every Deployment.
- The role creates the namespace, because nothing else did and everything after
  it assumes one.

**Verification**

`yamllint` and `ansible-lint` production profile clean. Rendered against the real
configuration, the role would create `oilscope-history`, `oilscope-fetcher` and
`oilscope-ui` from five distinct Secrets Manager ids.

**Left undone / follow-ups**

- **The step 5 open question is now live.** Deleting the per-VM grants left
  nobody with read access; this role answers it as "the operator, at deploy
  time", which means the `oilscope` profile needs `secretsmanager:GetSecretValue`
  on those five secrets. Nothing grants it explicitly. It will work if the
  profile is broad and fail with AccessDenied if not — after the namespace is
  created but before any secret lands.
- No `migration` entry exists in `secret_mappings`, so the migration Job in
  step 24 has no privileged credential yet.

---

## Step 22 — RabbitMQ

Status: `written, unverified` · Started: 2026-09-28 · Finished: 2026-09-28

**What was implemented**

- `infrastructure/helm/charts/oilscope-rabbitmq/`: a repository-owned chart over
  the official `rabbitmq:4.2.9-management` image — StatefulSet at one replica,
  headless ClusterIP Service on 5671, ConfigMap holding `rabbitmq.conf` and
  `definitions.json`, and a cert-manager Certificate from the internal CA.
- `definitions.json` is generated by a named template and its `sha256sum`
  annotates the pod, so a topology change rolls the StatefulSet instead of
  sitting unread in a ConfigMap.
- Schema: `secret_mappings` gained optional `rabbitmq` and `redis` keys, and the
  real configuration maps them to the ids their clients already use.
- Install wired into `deploy_k3s.yml` with `release_values` from the project
  configuration.
- `.yamllint.yml` ignores `infrastructure/helm/charts/*/templates/`.

**Decisions made**

- **StatefulSet, not Deployment, even at one replica.** RabbitMQ derives its node
  name from the hostname and stores data at
  `/var/lib/rabbitmq/mnesia/<nodename>`. A Deployment gives a random pod suffix,
  so the node name changes on every restart and the broker starts against an
  empty data directory — durable queues apparently vanish, with no error.
- **Quorum queues kept at group size 1.** Correcting the earlier T1 reasoning:
  Compose already runs single-replica quorum queues, and the `reliable-retry`
  policy uses `dead-letter-strategy: at-least-once`, which is quorum-queue-only.
  Classic queues would have silently downgraded the retry path to at-most-once.
- **`load_definitions` in `rabbitmq.conf` instead of `rabbitmqctl
  import_definitions`.** Compose applies the topology with a post-start exec;
  in Kubernetes that is fragile. Loading at boot is idempotent and needs no
  ordering.
- **A real leaf certificate instead of the CA doubling as the server cert.** The
  Compose config sets `certfile` to `ca.pem`; the chart uses the cert-manager
  leaf with DNS SANs matching the Service name.
- **Request equals limit at `memory_mb`** so `vm_memory_high_watermark.relative
  = 0.6` cannot be outrun by an OOM kill.
- The broker gets its own `secret_mappings` entry rather than reading
  `oilscope-history`'s copy of the same value.

**Verification**

`helm lint` passes. Rendered output confirms three quorum queues at group size 1
with the retry TTL and `x-delivery-limit: -1` in the right places, the
`reliable-retry` policy with `at-least-once`, the `prices` to
`price_observations` binding on `observations`, three correct DNS SANs, 8760h
duration with 2920h renewBefore, matched request and limit, and the password
sourced from `oilscope-rabbitmq`. All three configs still validate.

**Problems faced**

- `yamllint` cannot parse Helm templates — `{{ .Release.Name }}` reads as YAML
  flow braces, so the whole chart failed the repo's YAML job. CI would have
  failed on this.

**Left undone / follow-ups**

- **Password rotation does not happen by redeploying.** `RABBITMQ_DEFAULT_PASS`
  applies only on first boot with an empty data directory; once the PVC exists,
  changing the Secret has no effect. Compose handles this with a separate
  `rabbitmqctl change_password`. No automatic reset was added, because that is
  the "never regenerate credentials on a rerun" failure the plan warns about.
  Needs documenting as a manual step.
- `.venv-ansible/` is a 2 GB virtualenv in the repository root that `.gitignore`
  does not match — `.venv/` does not cover it. Nothing under it is tracked.
  Pre-existing.

---

## Step 23 — Redis

Status: `written, unverified` · Started: 2026-09-28 · Finished: 2026-09-28

**What was implemented**

- `infrastructure/helm/charts/oilscope-redis/`: StatefulSet at one replica over
  the official `redis:8.6.6` image, headless ClusterIP Service, PVC on
  `oilscope-gp3`, password from the `oilscope-redis` Secret.
- Server flags carried over from Compose unchanged: `appendonly yes`,
  `appendfsync everysec`, `maxmemory`, `maxmemory-policy noeviction`,
  `requirepass`.
- Install wired into `deploy_k3s.yml`.

**Decisions made**

- **No TLS inside the cluster for now** — a deliberate deviation from the plan,
  recorded in `docs/k3s-deployment.md`. RabbitMQ got TLS because it already spoke
  AMQPS and its client contract already carried a CA file. Redis is reached by
  URL, so `rediss://` needs the CA bundle mounted into the **UI pod** and the
  client verifying it — both ends changing together, and the UI end belongs to
  the application chart. Half of it here would leave a step that cannot be
  verified alone. Cost: session traffic crosses node boundaries in the clear on
  the pod network, inside the VPC.
- **`maxmemory` deliberately below the container limit** — 128mb against 256Mi.
  `maxmemory` counts data, not the AOF rewrite buffer, fork overhead or
  fragmentation; equalising them would let a background rewrite OOM-kill the pod.
- **`noeviction` kept.** These are sessions, so refusing writes is correct and
  evicting logins is not.
- `--requirepass "$REDIS_PASSWORD"` leaves the password in the container's
  process arguments, as Compose does. Not a new exposure — anyone who can exec
  into the pod can read the environment — but a config file would avoid it.
  Parity chosen over a silent divergence.

**Verification**

`helm lint` passes; rendered output confirms the server flags, matched request
and limit at 256Mi, the password sourced from `oilscope-redis`, and a 2Gi PVC on
`oilscope-gp3`. `yamllint` and `ansible-lint` production profile clean.

**Left undone / follow-ups**

- **Redis TLS**, to be closed in the application chart where the URL, the CA
  mount and `--tls-port` can change in one release.

---

## Step 24 — Database migration Job

Status: `written, unverified` · Started: 2026-09-28 · Finished: 2026-09-28

**What was implemented**

- `infrastructure/helm/charts/oilscope/` created as a skeleton — `Chart.yaml`,
  `values.yaml` and the migration Job. Deployments follow in step 26.
- The Job is a **Helm hook**: `pre-install,pre-upgrade`, weight `-5`,
  `before-hook-creation` delete policy, `backoffLimit: 0`, `restartPolicy: Never`,
  `activeDeadlineSeconds: 900`.
- `deploy_k3s.yml` reads `aws_database_connection` from the Terraform outputs,
  fetches the RDS master credential with the operator's identity, and creates an
  `oilscope-migration` Secret. All gated on `managed_database` and `no_log`.

**Decisions made**

- **A hook rather than a plain Job.** Helm waits for hook completion before
  creating any Deployment, so "completes before application rollout" comes free
  and a failed migration aborts the release instead of letting pods start against
  an unmigrated schema. A plain Job would have needed separate orchestration.
- **`backoffLimit: 0`.** A failed migration is a failure; retrying a
  half-applied one silently is worse than stopping.
- **The RDS master credential, not a dedicated migration role.** The isolation
  would be better, but creating that role is itself privileged — chicken and egg.
  Worth revisiting once a schema exists, since the role could then be created by
  a migration.
- The chart install is **not** wired into `deploy_k3s.yml` yet. Doing so now
  would make every run fail on an unpullable placeholder digest. Step 26 adds it.

**Verification**

`helm lint` passes. Rendered with a synthetic digest: one Job, correct hook
annotations, `petroscope-migrate` as the command, and the five `PG*` variables
plus `MIGRATION_PROFILE` wired from values and secrets. `yamllint` and
`ansible-lint` production profile clean.

**Problems faced**

- None, because `migrate.sh` was already a good fit — `ON_ERROR_STOP=1`,
  `set -eu`, a `pg_isready` wait loop, and everything driven from `PG*`
  environment variables.

**Left undone / follow-ups**

- **Both migration profiles are empty.** `database/migrations/cloud/` and
  `application/` contain only `.gitkeep`; all four SQL files are in `common/`.
  So `MIGRATION_PROFILE: cloud` applies exactly the same migrations as
  `application` would. The profile distinction carries no content today — if the
  managed path was meant to have its own grants or role setup, that is missing
  rather than done.
- The Job cannot run until step 25 publishes real image digests.

---

## Step 25 — Publish and pull from the native registry

Status: `written, unverified` · Started: 2026-09-29 · Finished: 2026-09-29

**The publish half was already done** in step 9: `publish-pavlo.yaml` builds the
four images and pushes them to ECR over OIDC on a `pavlo-v*` tag. This step is
the pull half.

**What was implemented**

- `templates/registry-credentials.yaml` in the application chart: a
  ServiceAccount, a narrow Role, a RoleBinding and a CronJob refreshing an
  `oilscope-registry` dockerconfigjson Secret every 8 hours. An init container
  mints the token with the node role through IMDS; a second writes the Secret.
- `deploy_k3s.yml` seeds that same Secret at deploy time with
  `aws ecr get-login-password` under the operator's identity, and derives the
  registry host from the Terraform `registry` output.
- The migration Job references the Secret through `imagePullSecrets`.

**Decisions made**

- **Both (b) and (d), not (b) alone.** Building it surfaced a bootstrap hole:
  the CronJob cannot create the Secret the first deployment needs, because the
  first migration Job runs before any schedule fires. The deploy-time seed —
  which had been described as the insufficient option — turns out to be exactly
  the right bootstrap. Neither half works alone.
- **RBAC as narrow as the API allows.** `create` on secrets cannot be scoped by
  name, but `get`/`patch`/`update`/`delete` are limited to `oilscope-registry`.
  A compromised refresh pod cannot read the database or broker credentials in
  the same namespace.
- Both images pinned and verified with `docker manifest inspect` before use.

**Problems faced**

- **Option (a), the kubelet credential provider, is blocked.** It is the correct
  mechanism — a token minted per pull from the node role, nothing stored,
  nothing expiring — but AWS's `ecr-credential-provider` binary could not be
  sourced. `artifacts.k8s.io/binaries/cloud-provider-aws/...` returns 404 for
  every version tried; the GitHub releases carry no binary assets; and
  `public.ecr.aws/eks/ecr-credential-provider` has no such manifest for any tag.
  Building from source is the way to revisit it. Recorded in
  `docs/k3s-deployment.md` with an explicit instruction not to guess a URL.

**Verification**

`helm lint` passes. Rendered output confirms the five objects, the
`imagePullSecrets` reference on the migration Job, `concurrencyPolicy: Forbid`,
both pinned images, and the two-rule RBAC. `yamllint` and `ansible-lint`
production profile clean.

**Left undone / follow-ups**

- **The 12-hour fuse.** If the CronJob stops working, nothing breaks for up to
  12 hours and then every image pull fails — new pods, rescheduled pods,
  replaced nodes. Running pods are unaffected because the image is cached, which
  is what makes it easy to miss. Monitor the CronJob's failed-job count.
- `publish-images.yaml` still pushes to GHCR on every `develop`/`main` push,
  building images nothing deploys. Retiring it is a decision about whether GHCR
  stays a mirror.
- The digests in the configuration are still placeholders until a `pavlo-v*` tag
  is pushed.

---

## Step 26 — Application chart

Status: `written, unverified` · Started: 2026-09-29 · Finished: 2026-09-29

**What was implemented**

- Deployments, Services and an Ingress for UI, History and Fetcher in
  `charts/oilscope/`, plus `_helpers.tpl` for labels, the shared broker
  environment block and topology spread.
- `roles/k3s_urls/`: composes `DATABASE_URL`, `RABBITMQ_URL` and `REDIS_URL` and
  patches them into each workload's Secret.
- Redis TLS closed — the deferral from step 23.

**Decisions made**

- **Redis TLS needs no application change.** Verified against redis-py 8.1.0
  that `Redis.from_url` passes query parameters through as connection kwargs, so
  `rediss://…?ssl_ca_certs=…&ssl_cert_reqs=required` gives an `SSLConnection`
  with the CA path honoured. Redis now runs with `--port 0`, disabling plaintext
  entirely rather than listening on both.
- **URLs are composed in Ansible, not at pod start.** The services read
  `DATABASE_URL`/`RABBITMQ_URL`/`REDIS_URL` only — no `PGHOST`/`PGPASSWORD`
  support — so the password has to be URL-encoded into a DSN, which `envFrom`
  cannot do. Composing where the passwords already are avoids an init container.
  It also preserves the detail that would have been easy to flatten: History uses
  `postgresql+psycopg://` and Fetcher uses `postgres://`.
- **Liveness is `tcpSocket`, readiness is `httpGet /health`.** `/health` reports
  on the database and Redis, so using it for liveness would restart every
  History pod on a 30-second RDS blip — a recoverable outage turned into a
  cascade.
- **Fetcher uses `Recreate`** because `FETCH_ON_STARTUP: "true"` plus a cron
  means a rolling update briefly runs two schedulers, both fetching.
- **`SESSION_COOKIE_SECURE` changed from `"false"` to `"true"`.** Compose sets
  false because it serves HTTP behind a VM edge proxy; behind an HTTPS ingress
  that would mark session cookies non-secure.
- **CA bundles mount only the `ca.crt` key**, not the whole Secret — otherwise
  every application pod would hold the server's private key.
- **UI and History at one replica each** (operator decision). App requests total
  416Mi; with RabbitMQ and Redis that is 1440Mi across three 2 GiB nodes, which
  makes the `small` sizing comfortable rather than marginal.

**Verification**

`helm lint` passes; the chart renders 11 objects with the expected replicas,
strategies, probe split, `envFrom` wiring, topology spread and CA mounts, and an
Ingress on class `oilscope` with the cert-manager annotation. `yamllint` and
`ansible-lint` production profile clean.

**Problems faced**

- `ansible-lint` enforces role-prefixed variables, so the role was renamed from
  `k3s_connection_urls` to `k3s_urls` rather than lengthening fifteen variable
  names.

**Left undone / follow-ups**

- **Network policies were left out.** They were in scope, but they interact with
  the ACME HTTP-01 solver, CoreDNS and the IMDS access the registry CronJob
  needs — getting them wrong fails closed in ways that look like unrelated
  breakage. Worth doing deliberately.
- **History rolls with two consumers briefly.** `RollingUpdate` at one replica
  defaults to `maxSurge: 1, maxUnavailable: 0`, so the new pod starts before the
  old terminates. If concurrent consumption could double-publish from the
  outbox, History wants `Recreate` like Fetcher.
- The chart is still not wired into `deploy_k3s.yml`; the digests are
  placeholders.

---

## Step 27 — `managed_database: false`

Status: `not implemented, guarded` · Decided 2026-09-29

**Decision.** The self-hosted database branch is not built. A single-replica
PostgreSQL on the same three 2 GiB nodes would be **strictly worse than RDS**,
not merely unbuilt:

- **Durability** — RDS provides `backup_retention_days` automatically; in-cluster
  gives a PVC and nothing else. With step 16 deferred there is no backup
  machinery, so it would be the only durable data in the cluster with no copy.
- **Availability** — losing the node holding its PVC means downtime until the pod
  reschedules, and the volume is zonal, which only works because the deployment
  is single-AZ.

No cost saving offsets that at `db.t4g.micro`.

**What was implemented instead**

- `deploy_k3s.yml` refuses to run when `managed_database` is false, with a
  message naming what would otherwise happen — Terraform skips RDS, and the
  playbook composes a `DATABASE_URL` pointing at a host that never gets created.
- The full specification is kept in the step guide for whenever it is picked up.

**Tension worth recording.** House rule 4 forbids assertions and validations in
Ansible, and this is a validation gate in spirit even though it uses
`ansible.builtin.fail` rather than `assert`. Two things argued for it: the plan
itself asks to "fail clearly if this branch is not implemented", and
`roles/database_migrate/tasks/read_secret.yml` already uses `fail` the same way
for an unsupported cloud. A config that validates and then produces a silently
broken deployment seemed the worse outcome. Easy to remove if the rule is meant
to be absolute.

**Left undone / follow-ups**

- Step 31's "both database modes work" check is now untestable, like the step 16
  restore checks. It should be marked as such rather than quietly passed.
- `postgres:18.6-bookworm` stays pinned and verified in `versions.yml`, so
  picking this up later does not start from nothing.

---

## Step 28 — CI

Status: `done` · Started: 2026-09-29 · Finished: 2026-09-29

**What was implemented**

- Removed `terraform test` from `pr-validation.yml`. Zero `.tftest.hcl` files
  exist and under house rule 4 none will, so the line reported success having
  checked nothing.
- New `canary` job running `node --test health.test.js`.
- New `helm` job: `helm lint` over the four repository-owned charts,
  `helm template` over all six including Traefik, EBS CSI and cert-manager at
  their pinned versions and values files, then `kubeconform -strict` against
  Kubernetes 1.36.

**Decisions made**

- **Render the upstream charts too, not just the owned ones.** That is what
  would have caught the four wrong Traefik values keys at step 19, and it means
  a pinned chart version that stops matching its values file fails in CI rather
  than mid-deploy.
- `-ignore-missing-schemas` so CRDs without a published schema skip rather than
  fail, while core resources are still `-strict`.

**Problems faced**

- None, because every step was run locally first rather than written and hoped
  for.

**Verification**

Run locally exactly as CI would: all six charts render (16,710 lines),
`kubeconform` reports `98 resources found in 6 files - Valid: 92, Invalid: 0,
Errors: 0, Skipped: 6`, the canary suite passes 6/6, and `yamllint` is clean on
the workflow.

**Left undone / follow-ups**

- **The Helm job proves templates are valid, not that the real values work.** It
  renders with synthetic digests and example hostnames, because the real
  configuration lives outside the repository — the same limit as the schema
  question at step 2.
- `kubeconform` fetches schemas over the network, including the CRDs catalog from
  GitHub. A transient failure is a red build unrelated to the change. If it
  proves flaky, cache the schemas rather than dropping the check.
- The nine Compose-era `roles/*/tests/` directories remain. Rule 4 forbids them,
  but they belong to the deployment path that ends when Compose is retired.

---

## Step 29 — Monitoring for the cluster

Status: `written, unverified` · Started: 2026-10-02 · Finished: 2026-10-02

**What was implemented**

- `charts/oilscope/templates/cluster-metrics.yaml`: a ServiceAccount, ClusterRole,
  ClusterRoleBinding, ConfigMap and CronJob. Every 5 minutes a `kubectl` init
  container counts four things from the Kubernetes API into an in-memory volume,
  and an `aws-cli` container publishes them as CloudWatch gauges.
- `modules/aws/monitoring/cluster.tf`: four alarms on `NodesNotReady`,
  `PodsNotReady`, `JobsFailed` and `CertificatesNotReady`, all `> 0` with
  `treat_missing_data: breaching` so a dead collector also alarms.
- `modules/aws/vm/monitoring.tf`: the `cloudwatch:namespace` condition now
  allows the cluster namespace alongside `CWAgent`.

**Decisions made**

- **The narrow version.** Node readiness, PVC capacity and the CronJob alarm were
  described as the cheap wins, but all three need the same thing — something
  in-cluster publishing to CloudWatch, because there is no agent in the cluster.
  Once that collector exists, four API-derived gauges are nearly free.
- **`JobsFailed` is the important one.** It is what makes the step 25 registry
  refresh observable; without it the 12-hour fuse breaks every image pull with
  no signal.
- **`treat_missing_data: breaching`** so the collector silently dying is itself
  an alarm, rather than looking like health.

**Problems faced**

- The node role's `PutMetricData` was conditioned on
  `cloudwatch:namespace = CWAgent` only, so the collector would have been denied.
  A `put-metric-data` failure inside a CronJob is the kind of thing found months
  later while wondering why an alarm never fires. Checked before writing rather
  than after.

**Verification**

`helm lint` and `kubeconform` pass — 103 resources, 97 valid, 0 invalid.
Terraform `fmt`/`validate` clean, 78 AWS resources planned including the four
alarms. The shell counting was tested against sample inputs: three ready nodes
gives 0, one NotReady gives 1, an `Unknown` condition gives 1 (a node whose
kubelet stopped reporting is `Unknown`, not `False`), and no nodes at all gives 0
rather than a non-zero `grep` exit.

**Left undone / follow-ups**

- **PVC capacity is not covered.** It needs `kubelet_volume_stats_used_bytes`
  scraped and parsed from each kubelet's Prometheus endpoint — a different shape
  of work from four API queries. A real gap: with Redis on `noeviction` and
  RabbitMQ on `reject-publish`, a full volume means rejected writes rather than a
  crash, so it fails quietly.
- **`collect.py` is still Compose-shaped** (`docker ps --filter
  label=com.docker.compose.project=…`) and `monitoring-metrics.json` is still
  keyed by roles that no longer exist. Both are inert only because
  `application_metrics_enabled` defaults false — turning it on yields zero alarms
  and no error. A trap, not a feature.
- etcd snapshot age is moot while step 16 is deferred.

---

## Step 30 — Documentation

Status: `written, unverified` · Started: 2026-10-02 · Finished: 2026-10-02

**What was implemented**

- `docs/k3s-deployment.md`: the operator document. Credentials and where each is
  read from, the six-command first run, `helm diff`-less "see what would change"
  via `--dry-run`, and a rollback table. Then, to satisfy the step's own "done
  when", the firewall matrix from step 6 — which existed only as one prose
  sentence covering 22/80/443/6443 and omitted every intra-cluster rule.
- Scope notices at the top of four documents that are now partly false on AWS:
  `docs/supported-compose-deployment.md`, `docs/monitoring.md`,
  `docs/secrets.md`, `infrastructure/ansible/inventory/README.md`.
- `docs/ci-required-checks.md`: added the four job names it never listed
  (`Docker image (database)`, `Ansible Lint`, `Helm`, `Synthetics canary`),
  rewrote the `Terraform` rationale, and added a section on what `Helm` does and
  does not prove.
- `README.md`: a "Deployment paths" table near the top, Helm/k3s in the
  technology stack, `ansible/`/`helm/`/`terraform/` in the repository layout, the
  ECR publish path alongside the GHCR one, `managed_database: true` being forced
  on AWS, the schema being k3s-only, the bastion's removal, and two security
  bullets on `admin_allowed_cidrs` and the kubeconfig.

**Decisions made**

- **Scope notices rather than deletion.** GCP and Azure still run the Compose
  path, so those documents are live for two of three clouds. A banner saying
  which parts no longer apply is honest; deleting them would strand the clouds
  that have not been converted.
- **Both registry paths documented, not one.** GHCR is still what Compose pulls.
  The README now says plainly that the AWS path uses neither those images nor
  moving tags, instead of quietly replacing the section.
- **The bastion's removal written up as a loss, not an improvement.** Three
  nodes with Elastic IPs behind an allow-list is less isolated than a bastion.
  The README says so and points at this log rather than describing it as
  simplification.
- **The `terraform test` removal recorded where it is visible.** A step that
  passed having asserted nothing is worse than no step, because the required
  check name reads as coverage. That belonged in the CI document, not only here.

**Problems faced**

- `docs/ci-required-checks.md` carried a section titled "Why `Terraform` is safe
  to require now", whose entire argument was that there is no Terraform in the
  repository. The mechanism it described — job-level `if:` produces no status, so
  gate at step level instead — is still exactly what the job does, and is worth
  keeping; only its premise had rotted. Rewritten around the real trigger (a diff
  against `infrastructure/terraform/`) rather than deleted.
- Wrote that `Helm` lints four charts; there are three (`oilscope`,
  `oilscope-rabbitmq`, `oilscope-redis`). Counted the directory.
- Wrote that the fetched kubeconfig is not covered by the `forbid-secret-files`
  pre-commit hook — true but irrelevant: `k3s_kubeconfig` writes it to
  `~/.kube/<context>.yaml`, outside the repository, so no hook or `.gitignore`
  entry is load-bearing. The bullet now says where it lands and why every call
  needs `--kubeconfig`.
- The README's claim that AWS "puts the bastion and the UI in the management
  subnet" was two topologies out of date, and the NAT gateway it implied is gone
  too. Checked `modules/aws/network/routing.tf` before rewriting: one subnet, a
  public route table to the internet gateway, and a routeless private table for
  the two RDS subnets.
- Re-reading `docs/k3s-deployment.md` against step 30's "done when" turned up
  three defects in the document itself, all of which would have shipped:
  - it said "three rules therefore hold only because an operator upholds them"
    above **four** bullets, and closed with "check all three by eye" — so an
    operator counting the list would not know which one to drop;
  - the machine-size table listed Azure `small` as `Standard_B2s` — 2 vCPU /
    4 GiB. The real `size_map` has `Standard_DC1s_v3` for `small` *and* for
    `micro`: 1 vCPU / 8 GiB, the same size for both tiers. A table copied from
    the plan rather than read out of the configuration;
  - the firewall section covered only the four ports an operator can see from
    outside. Every rule that makes the cluster work — etcd's 2379/2380, kubelet's
    10250, and Flannel's 8472 on **UDP** — was absent, which is exactly the set
    where a wrong rule yields a cluster that forms and then misbehaves.

**Verification**

Claims checked against the code rather than from memory: the job names and the
`--set` placeholders from `.github/workflows/pr-validation.yml`; the owned chart
count from `infrastructure/helm/charts/`; the subnet and route-table shape from
`modules/aws/network/`; the kubeconfig destination and mode from
`roles/k3s_kubeconfig/defaults/main.yml`; and `role` being `const: "kubernetes"`
with `network.additionalProperties: false` from the schema, which is what makes
the README's "the current schema rejects it" true rather than aspirational.

No linter covers Markdown in this repository, so the table alignment and link
targets are eyeballed, not checked.

**Left undone / follow-ups**

- **`docs/database-modes.md` has no scope notice.** It is about switching
  `managed_database`, which on AWS cannot be switched. It should say so.
- **`docs/security-scanning.md` and `docs/dns.md` were not reviewed** against the
  k3s path in this step. `dns.md` was rewritten earlier with the DNS work;
  `security-scanning.md` predates everything and may describe an `IaC scan` scope
  that no longer matches.
- **The Compose documents will have to be deleted eventually**, and nothing
  schedules that. It happens when GCP and Azure are converted, which is not
  planned.
- **The README is long and now qualifies with "on AWS" in seven places.** Once the other
  clouds are converted, most of those qualifiers collapse — but until then,
  removing them would make the document wrong for two clouds out of three.

---

## Step 31 — Verification on disposable infrastructure, then cutover

Status: `not started` · Started: ____-__-__ · Finished: ____-__-__

**What was implemented**

-

**Decisions made**

-

**Problems faced**

-

**Left undone / follow-ups**

-

---

# Closing summary

Written after step 31.

**What the deployment actually looks like**

-

**Where the implementation diverged from the plan, and why**

-

**What the house rules cost in practice**

Filled in honestly at the end — whether dropping preflight, Terraform validations
and code comments made the work faster overall, and what it cost when something
broke.

-

**Review findings (R1–R18): how each was resolved**

| Finding | Resolution |
| --- | --- |
| R1 Cloudflare DNS module | |
| R2 Staging canary alarms | |
| R3 Three-AZ spread | |
| R4 Subnets and orphaned management CIDR | |
| R5 `tags` vs `network_tags` | |
| R6 `disk_type: ssd` → `io2` | |
| R7 Duplicate SSH CIDR fields | |
| R8 `size: kubernetes` | |
| R9 Cost increase | |
| R10 Azure credentials for every plan | |
| R11 `rabbitmq.certificate_days` | |
| R12 Container memory mapping | |
| R13 Staggered etcd snapshots | |
| R14 Break-glass path | |
| R15 Compose deprecation | |
| R16 No CI deployment path | |
| R17 `docs/dns.md` reasoning | |
| R18 Schema validation not enforced | |

**Real monthly cost vs. the step 1 estimate**

-

**What I would do differently**

-
