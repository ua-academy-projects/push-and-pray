# k3s deployment — implementation steps

Companion to [IMPLEMENTATION_PLAN.md](../IMPLEMENTATION_PLAN.md). The plan says
*what* the end state is and records 18 review findings (R1–R18) against it. This
document turns both into an ordered list of steps you can work through one at a
time.

Record the outcome of each step in [k3s-implementation-log.md](k3s-implementation-log.md)
before starting the next one.

## House rules

These four constraints apply to every step below and have already been folded
into them. They are listed here because they change what "good" looks like in
ways that will surprise anyone reading the plan alone.

1. **No comments in code.** Terraform, Ansible YAML, Python, Go — none. Write
   code that reads without them and put explanation in `docs/`. When a comment is
   wrong, delete it rather than correcting it.
2. **Module calls in `main.tf` pass only the config object and other modules.**
   No extra scalar arguments. A new module takes `variable "config"` plus module
   references and derives everything else internally.
3. **Root `locals` stay short.** Anything derivable is computed inside each
   module from `var.config`, not normalized once at the root. This duplicates
   derivation across the three cloud module trees; that is the accepted cost.
4. **No tests, assertions or validations in Terraform or Ansible.** No
   `.tftest.hcl`, no `variable` `validation`, no `lifecycle` `precondition`, no
   `check` blocks, no `assert` tasks, no `roles/*/tests/`. And, by your step 1
   decision, **no preflight playbook in the k3s path at all**.

## Scope: AWS first

Decided 2026-09-25. Every step below is implemented for **AWS only**. The GCP and
Azure equivalents are done separately, by hand, afterwards. The three cloud
module trees are independent implementations of the same contract, so this does
not change any step's content — it changes how much of each step is done in one
pass.

The GCP and Azure trees are not edited here at all, including one-line shims to
keep a plan running. That has a consequence for every remaining Terraform step:
all three trees are instantiated unconditionally in `main.tf`, so
`terraform plan` **cannot complete** while a non-AWS module reads a removed
configuration key — currently `modules/azure/network/locals.tf:31`.

So the *Done when* of every Terraform step below means: `fmt -check` and
`validate` are clean, and no error in the plan output names a file under
`modules/aws/` or at the root. Errors from `modules/azure/`, `modules/gcp/` and
provider credentials are expected and are not regressions. Verify with
`project-config.cloud-example.json`; the GCP example is not expected to work.

### What rule 4 costs, stated plainly

The plan's section 3 item 2 requires a preflight that validates topology, routes,
DNS, CIDR overlap, disk capacity, local tool versions and image access before any
change. That is dropped. The plan's section 9 check "invalid or unreachable
public/private address combinations fail before deployment" is now satisfied only
to the extent `project-config.schema.json` can express it — and it cannot express
CIDR overlap at all. A config with `pod_cidr` overlapping `service_cidr` will be
accepted everywhere and will surface as a cluster that half-works after step 14.

There is also no automated check on the configuration itself. The project
configuration lives outside the repository and is never committed, so a
pre-commit hook or a CI job would only ever see the committed *examples* — never
the file an operator actually applies. Both were therefore rejected as theatre.

**So nothing validates a real project configuration automatically.** Not
Terraform, not pre-commit, not CI. `project-config.schema.json` remains the
written contract and a check you can run by hand:

```sh
uvx check-jsonschema \
  --schemafile infrastructure/terraform/project-config.schema.json \
  /absolute/path/project-config.json
```

Every constraint written into the schema in step 3 is advisory in exactly this
sense: it catches a mistake when someone chooses to run that command, and not
otherwise. Write the schema anyway — it is the contract, and the command is
cheap — but do not design any later step around the assumption that a bad config
cannot reach `terraform apply`. It can.

## How to use this document

- **One step, one branch, one commit series.** Every step has a *Done when*
  section that is checkable without the next step existing. If you cannot check
  it, the step is not finished — do not roll it into the following one.
- **Steps are ordered by dependency, not by size.** Step 6 is a week; step 4 is
  an afternoon. The order matters more than the balance.
- **Nothing here provisions cloud resources until step 31.** Everything before it
  is code, `terraform plan`, `helm template` and lint. The one exception is the
  disposable cluster you will want from step 14 onward — use a throwaway
  project/account, never the live one.
- **Azure credentials are needed for every `terraform plan`**, even an AWS-only
  one, because Azure shares the single Terraform root (R10). Budget for that
  before the first plan run in step 6.

## Notation

- **Goal** — what exists at the end that did not exist at the start.
- **Why here** — what makes this the right position in the order.
- **Files** — what you will touch. Paths are repo-relative.
- **Do** — the work.
- **Decide** — a choice the plan leaves open; my recommendation is first.
- **Done when** — the check.

---

# Phase 0 — Guardrails and frozen decisions

## Step 1 — Freeze the open decisions from the review findings

**Goal.** A written, dated decision record covering every review finding that
changes the shape of the configuration, so Phase 1 is written once.

**Why here.** R5 (`tags` vs `network_tags`), R6 (`disk_type`), R8 (`size`) and
R3 (zones) each change the JSON fragment in the plan's section 1. If you write
the schema first and decide afterwards, you rewrite the schema, the example
config and everything that reads them.

**Files.** `docs/k3s-implementation-log.md` (the decision table at the top).

**Decided 2026-09-25.** The table below is the input that produced those
decisions; the answers, including four topology decisions (T1–T4) that the
findings did not anticipate, live in the log. Read the log, not this table, for
what was actually chosen.

**Decide.** My recommendation for each, all of which you can override — but
override *in writing*:

| Finding | Recommendation | Reasoning |
| --- | --- | --- |
| R5 `tags` key | Use the existing `network_tags: ["control-plane", "worker"]`. Delete the `tags` concept and the normalization step in plan section 1 bullet 3. | `$defs/vm` has `additionalProperties: false`, so `tags` is rejected outright, and `network_tags` already drives firewall rules in all three cloud modules. Two keys meaning the same thing will drift. |
| R6 `disk_type: "ssd"` | Use `"balanced"`. | `ssd` maps to `io2` on AWS — provisioned IOPS with a per-IOPS charge and a provisioning floor. `balanced` maps to `gp3`, which is SSD and the normal etcd choice. |
| R8 `size: "kubernetes"` | Use an existing size key, not a new one. | `size_map` keys describe machine capacity (`micro`…`large`). A workload-named key can never be reused and tells a reader nothing. |
| R9 node size + cost | **Decided: `small`.** Write the expected monthly figure into the log and check `budgets.*.monthly_amount` against it *before* step 31. | The plan replaces ≈ $33/month of infrastructure with ≈ $260–290 at `large`. `medium` puts it near $150. The actual workload is three small services, RabbitMQ capped at 768 MB and Redis at 128 MB, on a k3s server with Traefik and ServiceLB disabled. Measure, then resize up if the evidence says so. |
| R3 three availability zones | Single zone initially. State the 3-AZ spread as a follow-up with its own `region_map` restructure. | `region_map` carries one zone per cloud as a scalar. Reaching three zones means changing it to an ordered list and threading zone selection through all three VM modules plus every disk that inherits zone from the VM. On AWS it also bills continuous inter-AZ transfer for etcd raft traffic forever. |
| R7 `admin_allowed_cidrs` | Cluster-level field replaces the per-VM `allowed_cidrs`; the schema deletes the per-VM key outright. | Two places restricting SSH to the same node is how one of them gets forgotten. |
| R11 `rabbitmq.certificate_days` | Reinterpret it as the cert-manager `Certificate` duration. | A config key that silently stops having an effect is worse than a removed one. |
| R14 break-glass | Pick one and write it down: (a) provider serial/console access documented in the recovery runbook, (b) a documented `admin_allowed_cidrs` update that applies without cluster access, or (c) keep one minimal bastion. I recommend (a)+(b). | With the bastion gone, all three nodes expose SSH and 6443 restricted only by `admin_allowed_cidrs`. A residential IP rotation locks you out of both SSH and `kubectl` with no jump host left. |
| R15 Compose path | **Superseded 2026-09-25.** The schema accepts only the k3s layout, so the Compose path ends at step 3 rather than after cutover. | Nothing can produce a valid Compose configuration any more. |
| R16 laptop-only Helm | Accept it as a known limitation, and add `helm diff` to the runbook so drift is visible before applying. | CI cannot deploy and live state cannot be reconciled against Git. That is defensible, but only if it is written down rather than discovered. |
| Preflight (house rule 4) | Confirm: no preflight playbook in the k3s path. | Already decided. Record it as a deviation from plan section 3 item 2 so a later reader does not think it was forgotten. |

**Done when.** The decision table in the log is filled in with your answers and
today's date, and the "Recommendation" column has been replaced by "Decision".

---

## Step 2 — Remove the false validation claims

**Goal.** Nothing in the repository claims a check exists that does not.

**Why here.** Before the schema is rewritten in step 3, because step 3's value
depends on knowing exactly what the schema is and is not. Two places currently
promise enforcement that was never implemented, and a reader who believes them
will skip the manual check.

**Why it is not the enforcement step it started as.** Adding a pre-commit hook
and a CI job was the original plan and was rejected: the project configuration
lives outside the repository and is never committed, so both would only ever
validate the committed *examples*. A green check that never sees the file being
applied is worse than no check, because it reads as coverage. The schema stays a
manual, opt-in command.

**Files.**
- `infrastructure/terraform/modules/cloudflare/dns/main.tf`
- `docs/dns.md`

**Do.**
1. `modules/cloudflare/dns/main.tf` carried a comment telling the reader to "see
   the `proxied` validation in variables.tf". There is no validation there —
   `proxied` is declared `optional(bool, false)` with no `validation` block, and
   there is no `check` block or precondition anywhere in the tree. Under house
   rules 1 and 4 the fix is to **delete the comment**, not to add the validation
   it describes. Remove the file's other comments at the same time; the TTL
   reasoning is already in `docs/dns.md` and the `coalesce` note describes a
   precondition that step 8 removes.
2. `docs/dns.md` stated that "Terraform therefore refuses `proxied: true` with an
   explanatory error". Replace it with what is actually true: the schema pins
   `cloudflare.proxied` to `false`, nothing applies that schema automatically,
   and `proxied: true` reaches `terraform apply` intact. Give the manual command
   inline so the reader can act on it.

**Left for step 8.** `docs/dns.md` also says Terraform "rejects a hostname that
sits outside the zone". That one is true today — a `lifecycle` precondition
enforces it. Step 9's rewrite deletes that precondition under house rule 4, so
the sentence becomes false at that point and has to be corrected then. Noted in
the log's cross-cutting table so it is not missed.

**Done when.** `grep -rn '#' infrastructure/terraform/modules/cloudflare/dns/`
returns nothing, and every enforcement claim in `docs/dns.md` names a mechanism
that exists.

---

# Phase 1 — Configuration contract

## Step 3 — Schema: replace the Compose layout with the k3s layout

**Goal.** `project-config.schema.json` describes the three-node k3s topology and
nothing else. A Compose-shaped configuration is rejected.

**Why here.** The schema is the contract every later phase reads. Nothing enforces
it automatically (see *What rule 4 costs*), so it is documentation plus an
opt-in command — which makes getting it right and getting it *read* the whole
value.

### This is a replacement, not a branch

There is no `deployment_target`, no `if`/`then` on it, and no Compose `else`
branch. That removes the hardest part of the original plan: JSON Schema
conditionals can only ever *add* constraints, so supporting both layouts would
have meant moving eight existing Compose assumptions into conditional branches
before adding anything. Deleting the Compose layout outright means you rewrite
those eight in place instead.

I recommend dropping `deployment_target` from the design entirely. A field with
one legal value is noise, and its stated purpose — stopping a routine redeploy
from silently converting a running deployment — is no longer something a config
flag can provide. See the safety note in step 31, which now carries that
responsibility.

**Files.** `infrastructure/terraform/project-config.schema.json`.

**Do.** Each of these is an edit in place, not a new branch:

1. `$defs/vm.role.enum` → `["kubernetes"]` only.
2. Delete the three rules in `$defs/vm.allOf`. All of them are about `bastion`
   and `ui` roles that no longer exist: the `assign_public_ip` → role
   restriction, the bastion `ssh_port`/`allowed_cidrs` rule, and the `ui` →
   `public_endpoint` rule.
3. **Delete `ssh_port`, `allowed_cidrs` and `public_endpoint` from
   `$defs/vm.properties`.** With `additionalProperties: false` already set, they
   are then rejected outright. This is how R7 gets satisfied — the per-VM key
   cannot be written at all, so there is only one place SSH sources are
   configured. It also stops `public_endpoint` competing with `ingress.hostname`.
4. `$defs/vm_network_tags.items.enum` → `["control-plane", "worker"]`, replacing
   `bastion`, `infra`, `history`, `fetcher`, `ui`.
5. `properties.vms`: drop `required: ["bastion"]` and `properties.bastion`; set
   `minProperties: 3` and `maxProperties: 3`; make `additionalProperties`
   require `role: "kubernetes"` and `network_tags` containing both tags:

   ```json
   "network_tags": {
     "allOf": [
       { "contains": { "const": "control-plane" } },
       { "contains": { "const": "worker" } }
     ]
   }
   ```

   Keep the existing `propertyNames` pattern — `k3s-1` / `k3s-2` / `k3s-3`
   already satisfy it.
6. `properties.network`: remove `management_subnet_cidr` from both `properties`
   and `required` (your R4 decision). `ui_public_ports` already contains 80, so
   the HTTP-01 solver needs nothing new here.
7. `properties.registry`: replace `repository` / `username` / `image_sha` with
   the cloud-native shape — repository names, location, and an immutable digest.
8. `properties.rabbitmq` and `properties.redis`: delete `host_vm` from
   `properties` and from `required`.
9. Root `allOf`: **delete both `managed_database` VM-role rules.** The `true`
   branch forbids a `role: "database"` VM, which can no longer exist; the `false`
   branch *requires* one, which would make step 27's in-cluster PostgreSQL
   unreachable. Keep the `database_profile` requirement from the `true` branch —
   that is still meaningful. Keep all the `default_cloud` → `clouds.*` rules and
   the per-cloud managed-database network rules unchanged.
10. Add the `kubernetes` object: `version`, `entry_node`, `ssh_address_mode`,
    `admin_allowed_cidrs`, `api_endpoint`, `pod_cidr`, `service_cidr`,
    `namespace`, and the `etcd` sub-object (`snapshot_schedule_cron`,
    `snapshot_retention`, `backup_destination`).

    `entry_node` names the one node both hostnames resolve to. It must match a key
    in `vms`, and **JSON Schema cannot check that** — it cannot compare one part of
    a document against another. A typo gives you a config that validates and a
    Terraform plan that fails on a missing map key. Add it to the operator rules in
    `docs/k3s-deployment.md` alongside the CIDR ones.
11. Add the `ingress` object: `hostname`, `acme_email`, `challenge_type`. `hostname` and `acme_email` can reuse
    the patterns from the `public_endpoint` object you deleted in item 3.
12. Use `description` rather than `$comment` for anything a reader should see —
    validators print `description`, and `$comment` is a comment by another name
    (house rule 1). There is one existing `$comment` in the root `allOf` you are
    editing anyway.

### One trap, if you do keep a conditional for anything else

An `if` that tests a property must also `require` it, or an absent property makes
`properties` vacuously true and the branch fires on everything. The three root
`default_cloud` → `clouds.*` rules omit `required` and are safe only because
`default_cloud` is in the root `required` list. Any new conditional you add on an
*optional* field needs the `required` line.

### What the schema cannot express — do not plan around these

JSON Schema has no way to compare sibling values, so none of the following is
checkable here, and under house rule 4 there is no second place to check them:

- **Duplicate `internal_ip` across the three nodes.** `uniqueItems` applies to
  arrays, not to the values of an object's properties.
- **An `internal_ip` outside `workload_subnet_cidr`.**
- **CIDR overlap** between `pod_cidr`, `service_cidr` and the subnet CIDRs.

All three produce a cluster that half-works at step 14 rather than an error.
Write them into `docs/k3s-deployment.md` as operator responsibilities. Do not
write a *Done when* that implies the schema rejects them.

**Done when.** A hand-written k3s config validates, and each of these fails with
a message naming the problem: two nodes, four nodes, a node whose `role` is not
`kubernetes`, a node missing the `worker` tag, a per-VM `allowed_cidrs` or
`ssh_port`, a `network_tags` value outside the new enum, and a `host_vm` on
`rabbitmq`.

**Both committed examples will now fail**, which is expected — they are Compose
configs. Step 4 replaces them.

```sh
uvx check-jsonschema \
  --schemafile infrastructure/terraform/project-config.schema.json \
  project-config.k3s-example.json
```

---

## Step 4 — A committed k3s example config

**Goal.** The committed examples describe the k3s topology, and the Compose ones
are gone.

**Why here.** You need a concrete config before Terraform can plan anything, and
after step 3 the two existing examples no longer validate against the schema.

**Files.** `project-config.example.json` and `project-config.cloud-example.json`
(replace or delete), a new k3s example, and `.gitignore`.

**Note on `small`.** `size_map.small` is `e2-small` / `t3.small` / `Standard_B2s`
— 2 vCPU and **2 GiB** on GCP and AWS, 4 GiB on Azure. The system overhead of a
k3s server with embedded etcd is roughly 0.6–0.9 GiB before any workload runs, so
a 2 GiB node has about 1.1–1.4 GiB for pods. In steady state the workload fits.
**Under one-node loss it does not**: two nodes then carry RabbitMQ's 768 MiB
limit, Redis, and five application pods, which is the scenario the three-node
design exists for. Watch memory on the surviving nodes during the step 31
one-node-loss test specifically, and treat resizing as expected rather than as a
failure.

**Decide: how many examples.** The two today are not redundant — they demonstrate
both database modes and two clouds: `project-config.example.json` is GCP with
`managed_database: false`, `project-config.cloud-example.json` is AWS with
`managed_database: true` and `database_profile: "economy"`. Both modes survive
into k3s (step 27), so I would keep two examples and convert them in place rather
than adding a third file with a new name. That also avoids the `.gitignore`
problem below.

**Watch `.gitignore`.** It ignores `*.json` and re-admits files one by one:
`!project-config.example.json` and `!project-config.cloud-example.json`. A new
filename such as `project-config.k3s-example.json` needs its own exception line
or it will silently never be committed — `git add` will appear to work and the
file will not be in the commit.

**Do.** Base it on `project-config.example.json` and apply the plan's section 1
fragment *as amended by your step 1 decisions*:

- three `vms` entries `k3s-1` / `k3s-2` / `k3s-3` — these already satisfy the
  existing `propertyNames` pattern `^[a-z][a-z0-9-]*[a-z0-9]$`, so no schema
  change is needed for naming;
- `role: "kubernetes"`, `network_tags: ["control-plane", "worker"]`, `size` and
  `disk_type` per your R6/R8 decisions;
- `secret_mappings: {}` on each VM — step 21 moves secret resolution to the
  operator's machine, so the key stays (it is `required` in `$defs/vm`) but
  empties out. Confirm that is what you want rather than removing it from the
  branch;
- no `public_endpoint` on any VM; the hostname now lives at `ingress.hostname`;
- no `host_vm` on `rabbitmq` or `redis`;
- `managed_database: true`.

**Done when.** `uvx check-jsonschema --schemafile infrastructure/terraform/project-config.schema.json project-config.k3s-example.json`
passes, and the Compose example still passes unchanged.

---

## Step 5 — Config plumbing, without growing the root

**Goal.** Every module can read the new configuration blocks, with no new entries
in `locals.tf` and no new arguments in `main.tf`.

**Why here.** Phase 2 modules all read the same config. Settle *how* they read it
before writing three cloud trees against it.

**Files.** `infrastructure/terraform/main.tf`, module `variables.tf` files.

**Do.**
1. Leave `locals.tf` alone. Do not extend `local.config` with normalized
   `kubernetes`, `ingress` or registry blocks, and do not add an `is_k3s` local.
   Each module derives
   its own defaults from `var.config` internally (house rule 3). There is no
   `deployment_target` to test — the configuration has one shape now.
2. Every module keeps a single `variable "config"`, plus module references where
   it needs another module's outputs (house rule 2). When a new module needs the
   VM set, take it from the VM module rather than adding a `vms` argument — the
   existing `gcp_secrets` and `aws_secrets` calls take `vms` as a separate
   argument and are the shape you are moving away from, not toward.
3. Rewire whatever step 4's move of `secret_mappings` broke. The three secrets
   modules and `outputs.tf`'s `workload_secret_access` all read
   `vms[].secret_mappings`, which no longer exists. Reading the top-level
   workload-keyed block instead also removes the `vms` argument from the module
   call, which is house rule 2 satisfied for free.
4. Decide whether per-VM `cloud` survives. A k3s cluster with embedded etcd
   cannot span clouds, so the override can only produce a broken cluster.
5. Write the defaulting pattern down in `docs/k3s-deployment.md` so all three
   cloud trees default the same way. With no shared local doing it, the only
   thing keeping them consistent is that they were written from the same
   description.

**The gap you are accepting.** The same `try(...)` default for, say,
`kubernetes.pod_cidr` will exist in several modules. If one is written with a
different fallback, nothing detects the divergence — there is no root local to
disagree with and no test to catch it. Grep for each new key before finishing
Phase 2.

**Done when.** `terraform validate` passes, `main.tf` contains no new scalar
arguments, `locals.tf` is unchanged, and a plan against the AWS example no longer
reports a `secret_mappings` error. It will still fail further along — the network
and VM modules are steps 6 and 7 — and `terraform validate` will not catch any of
it, because the configuration arrives through `jsondecode(file(...))` and its
attributes are only resolved at plan time.

---

# Phase 2 — Terraform: nodes, networking, endpoints

> All of Phase 2 shares one constraint worth repeating: the three cloud module
> trees are independent implementations of the same contract. A change to the AWS
> network module is not a change to the GCP one. Plan for three times the work
> you estimate from reading one of them — and, under house rule 3, three times
> the defaulting logic as well.

## Step 6 — Network modules: subnets and the firewall matrix

**Goal.** Each cloud's network module builds the k3s topology: no bastion, a
workload subnet holding all three nodes, and a rule set that matches k3s's actual
requirements.

**Files.** `infrastructure/terraform/modules/{aws,gcp,azure}/network/`.

**Do.**
1. Rewrite each module for the k3s topology in place — there is no Compose branch
   to preserve. Delete the bastion subnet, its security group / firewall rules,
   and the per-workload rules keyed off `history` / `fetcher` / `ui` roles.
2. Build the port matrix. Between nodes: TCP 6443 (API), TCP 2379–2380 (etcd),
   TCP 10250 (kubelet), UDP 8472 (Flannel VXLAN). From `admin_allowed_cidrs`
   only: SSH and 6443. From anywhere: TCP 80 and 443.
   `network.ui_public_ports` already holds exactly those two ports and keeps its
   meaning. HTTP-01 needs no new opening.

   **80 and 443 open on all three nodes, not only the entry node.** All three share
   one security group, so narrowing those two ports to the entry node means a
   second group and a second rule set. Leaving them open costs nothing — DNS only
   ever sends traffic to one address — and it is what makes the failover in step 8
   a DNS change rather than a DNS change plus a firewall change.
3. Keep etcd and overlay traffic private — no path from the internet to
   2379–2380, 10250 or 8472.
4. Verify the matrix against the *pinned* k3s release's documented requirements
   rather than from memory; k3s's defaults have changed between releases.

**Done when.** `terraform plan` on the k3s example produces no bastion resources
and a rule set you have checked line by line against
<https://docs.k3s.io/installation/requirements>. Paste the matrix into the log —
with no tests in the tree, that table is the only record of what you decided, and
you will need it again in step 31.

---

## Step 7 — VM modules: the `kubernetes` role

**Goal.** Three identical nodes are planned in each cloud, with role tags,
optional public IPs and no per-service identity assumptions.

**Files.** `infrastructure/terraform/modules/{aws,gcp,azure}/vm/`.

**Do.**
1. Accept `role: "kubernetes"` wherever the modules currently switch on role for
   networking, identity, database access, DNS and monitoring.
2. Apply provider tags/labels from `network_tags` (`oilscope-control-plane=true`,
   `oilscope-worker=true` or the provider's equivalent). Tags express membership
   only — they install nothing. Kubernetes role *labels* are applied in step 14,
   by Ansible, and are a separate thing.
3. Keep `assign_public_ip` per VM. For the optional reserved-address feature the
   plan asks for, accept a **reference to a provider reserved-address resource**
   rather than an address string. Under house rule 4 there is no validation to
   reject an arbitrary unowned IP, so design the input so there is nowhere to type
   one.
4. Export node identity, roles and both addresses for step 11's outputs.

**Done when.** `terraform plan` shows exactly three instances per cloud with the
expected tags, and nothing references a `history` / `fetcher` / `ui` VM.

---

## Step 8 — Point both hostnames at the entry node

**Goal.** Two DNS-only `A` records, both resolving to the `kubernetes.entry_node`
Elastic IP.

**Why here.** With no load balancer, DNS is the entry point, and this is the last
AWS-side module still written for the old topology.

**Files.** `infrastructure/terraform/modules/cloudflare/dns/`.

**Do.** The module is wired to the UI **VM** in four ways, all of which break:

1. `local.ui_vm_keys` filters `vm.role == "ui"`, which is now always empty.
   `one([])` returns **null** rather than erroring, and the `try()` around
   `hostname` and `ip_address` swallows the null index, so the locals evaluate
   quietly to `""`. The failure surfaces at the first `lifecycle` precondition —
   "the configuration has no VM with role \"ui\"" — which is a readable message,
   not a crash. Verified with `terraform console`.
2. `local.hostname` reads `vms[ui].public_endpoint.hostname`. That moved to
   `ingress.hostname` in step 3.
3. It publishes exactly one record. You need two: `ingress.hostname` and
   `kubernetes.api_endpoint`.
4. `local.public_ips` is a three-cloud map indexed by `default_cloud`. Only
   `aws_vms` matters, and the address to select is
   `aws_vms[var.config.kubernetes.entry_node].public_ip`.

`type = "A"` stays correct for both records — the target is a node's own IPv4
address. `proxied` stays false.

**Key the `for_each` by record purpose, not by address.** Something like
`{ ingress = ..., api = ... }`. Keying by IP would make an Elastic IP change a
destroy-and-recreate rather than an in-place update, and these records *are* your
ingress — a recreate is a brief NXDOMAIN on a live name.

**Keep `cloudflare.ttl` short.** It is no longer about a destroy/re-apply
allocating a new address; it is the floor on how fast the manual failover below
can take effect.

**Under house rules 1 and 4, the rewrite drops** the four `lifecycle`
`precondition` blocks and every comment. Those preconditions currently check that
a UI VM exists, the hostname is non-empty, the hostname sits inside
`cloudflare.zone_name`, and the address is IPv4. Afterwards a misconfigured zone
is a Cloudflare API error at apply instead of a clear message. Only the
zone-membership one is partly expressible in the schema, as a `pattern`; move the
rest into `docs/dns.md` as operator responsibilities.

**Also.** `docs/dns.md`'s central argument — why the record must never be
proxied — rests on TLS-ALPN-01 being answered by the origin on :443. You are on
HTTP-01 now, answered on :80. The conclusion holds, the reasoning does not; the
schema's `proxied` description names TLS-ALPN-01 explicitly too. And that file
claims Terraform "rejects a hostname that sits outside the zone", which is true
today via one of the preconditions this step deletes — so it becomes false in the
same commit. Fix both here.

**Done when** both hostnames plan a single `A` record each against the entry
node's Elastic IP, `proxied` is false, no precondition or comment remains in the
module, and `docs/dns.md` describes HTTP-01, the entry-node design and its failure
mode.

---

## Step 9 — Cloud-native container registry

**Goal.** Terraform provisions a private application repository per cloud, and CI
can authenticate to it without long-lived credentials.

**Files.** new `modules/{aws,gcp,azure}/registry/`, root wiring and outputs.

**Do.**
1. ECR (AWS), Artifact Registry (GCP), ACR (Azure), selected by `default_cloud`
   read from `var.config` inside the module. Support referencing an existing
   registry explicitly rather than always creating one.
2. Lifecycle/retention policies that **preserve the deployed and rollback
   digests**. A retention rule that deletes the image you would roll back to is the
   failure mode here.
3. Output repository URLs. Never output secret values.
4. Provision the GitHub Actions OIDC federation and a narrowly scoped publish
   role/identity. Avoid long-lived cloud credentials.
5. Provision a separate pull-only identity for the nodes.

**Done when.** `terraform plan` creates the repository and both identities per
cloud, and `terraform output` gives a repository URL that step 25 can consume.

---

## Step 10 — Decouple the database modules from VM roles

**Goal.** The managed database modules keep working when no `history` or `fetcher`
VM exists.

**Files.** `infrastructure/terraform/modules/{aws,gcp,azure}/database/`,
`modules/gcp/network/cloud_sql.tf`, `modules/azure/network/postgres.tf`.

**Do.**
1. Find every reference to a History/Fetcher VM role in access rules, private DNS
   and network attachment, and replace it with cluster identity and network
   outputs.
2. Restrict access to cluster-origin traffic. Account for pod egress SNAT: from
   the database's point of view traffic arrives from the *node* address, not the
   pod address — the allow-list must reflect that, and it differs by provider
   routing.
3. Keep private database DNS resolvable from pods. This is a step 31 check, but
   the records are created here.
4. Preserve the existing profile maps and TLS/CA handling untouched. An economy
   single-zone database is not made HA by this cluster; do not let the refactor
   imply otherwise.

**Done when.** `terraform plan` on the k3s example with `managed_database: true`
creates the database with no VM-role references anywhere in the diff.

---

## Step 11 — Cluster outputs

**Goal.** `terraform output` gives Ansible everything it needs. Ansible must never
guess an address.

**Files.** `infrastructure/terraform/outputs.tf`.

**Do.**
1. `bastion_public_ip` indexes `local.vm_public_ips["bastion"]` directly and will
   fail on a k3s config. Delete it.
2. The `workload_*` outputs all filter `if workload.role != "bastion"`, which now
   returns all three nodes. Replace them with a `cluster` output object rather
   than reusing the names — "workload" currently means "one VM per service",
   which is no longer true.
3. Export: node identity and roles, public and private addresses, SSH settings,
   API endpoint, ingress endpoint, database connection metadata, backup
   destination, registry URLs.
4. `outputs.tf` has its own `locals` block (`vm_names`, `vm_internal_ips`,
   `vm_public_ips`). Under house rule 3, do not grow it. Anything the cluster
   output needs should arrive as a module output already shaped, computed inside
   the module that owns it.
5. `workload_secret_access` derives from per-VM `secret_mappings`, which are now
   empty. Decide what replaces it — step 21 makes the operator's identity the one
   that resolves secrets.

**Done when.** `terraform output -json` on a planned k3s config contains every
value the step 13 inventory plugin and the step 17 Helm values will read, and
`terraform plan` still succeeds on the Compose example.

---

## Step 12 — Monitoring: stop the staging canary from alarming

**Goal.** The ACME staging window does not produce a continuously firing alarm.

**Why here.** Before any cluster exists, so the ordering constraint is encoded
rather than discovered during step 20.

**Files.** `infrastructure/terraform/modules/gcp/monitoring/uptime.tf`,
`modules/aws/monitoring/{synthetics,alarms}.tf`,
`modules/azure/monitoring/uptime.tf`, and the schema.

**R2 no longer applies.** It described a conflict between an ACME staging
certificate and monitoring that validates certificate trust — GCP's uptime check
sets `use_ssl` and `validate_ssl`, and AWS runs a real browser canary
(`syn-nodejs-puppeteer-*`), so both reject an untrusted chain and
`modules/aws/monitoring/alarms.tf` turns that into a firing alarm.

**Decided 2026-09-27: there is no staging environment.** `acme_environment` is
removed from the schema entirely and only real Let's Encrypt certificates are
ever issued, so the chain is always publicly trusted and the probes can always
verify it. The tolerant-TLS switch built for this step was removed along with the
field.

**What remains in this step** is the other half — the role-driven monitoring
logic that silently matches nothing under k3s.

**Files.** `modules/aws/monitoring/{locals,agent,application}.tf`.

**Do.**
1. `ui_vms` filters `role == "ui"` and is always empty. `logs_enabled` depends on
   it, so **log collection is off entirely** — no error, just nothing collected.
2. `workload_vms` filters `role != "bastion"`, which now means all three nodes.
   The name described a world where each VM was a service.
3. `agent.tf` maps roles to log files through a lookup table keyed by
   `ui`/`history`/`fetcher`/`database`. It returns `[]` for every node, and it is
   not fixable by renaming keys: it assumes one service per host with logs at
   `/var/log/oilscope/docker-<service>.log`, which is not how container logs
   work. Step 29 replaces it.

**Done when.** No `role ==` comparison remains in the module, and `logs_enabled`
reflects an actual setting rather than an empty set.

---
# Phase 3 — Ansible: bootstrap three dual-role nodes

> There is no preflight step in this phase. The plan's section 3 item 2 is
> dropped by house rule 4, so the first thing that touches a node is step 14's
> installer. A wrong address, an unreachable host or an overlapping CIDR now
> surfaces there, mid-run, rather than before any change. Take a snapshot or use
> a disposable cluster while iterating on this phase.

## Step 13 — Direct-SSH inventory

**Goal.** The three inventory plugins produce `k3s_servers` and `k3s_workers`,
with all three hosts in **both** groups, connected directly.

**Files.** `infrastructure/ansible/oilscope/platform/plugins/module_utils/oilscope_inventory.py`,
`plugins/inventory/oilscope_{aws,gcp,azure}.py`,
`infrastructure/ansible/inventory/*.yml`.

**Do.**
1. `oilscope_inventory.py`'s `bastion_ssh_port()` raises when it does not find
   exactly one VM with the bastion role. It now finds zero on every config.
   Delete it and the ProxyCommand wiring that depends on it, rather than
   branching — the Compose layout is gone from the schema, so there is no config
   that could take that path.
2. Remove the ProxyCommand for k3s hosts; connect to the public address, or the
   private one over an existing VPN/route, per `ssh_address_mode`.
3. Verify SSH host keys. Do not disable host-key checking to make direct
   connection work — that trades the bastion's security property for nothing.
4. Retain privilege escalation for host setup.
5. Both groups contain all three hosts. This is deliberate and is what makes every
   node schedulable in step 14.

**Note.** The module's docstrings describe the bastion and ProxyCommand design at
length. Under house rule 1, the rewritten parts come back without them; the
connection model belongs in `docs/k3s-deployment.md`.

**Done when.** `ansible-inventory --list` against a k3s config shows three hosts
in both groups with direct connection variables and no proxy, and the Compose
inventories are unchanged.

---

## Step 14 — Install k3s and form the cluster

**Goal.** Three k3s servers with embedded etcd, all schedulable, idempotent on
rerun.

**Files.** `playbooks/bootstrap_k3s.yml` (new), `roles/k3s_server/` (new), reuse
of `roles/host_baseline/`.

**Do.**
1. Pin a k3s release and install it with its bundled containerd. Reuse
   host-baseline tasks but **do not** install Docker — `roles/docker_engine/`
   is no longer used by any deployment path and can be removed once nothing
   references it.
2. Write identical server configuration to all three nodes.
3. Initialize `k3s-1` once with `cluster-init`. Join `k3s-2` and `k3s-3` as
   **servers** (not agents), sequentially, over the **private** bootstrap address
   with the shared protected token. Wait for readiness and etcd membership before
   each join. Use the private address specifically: joining over the public
   endpoint would route cluster-internal traffic out and back for no reason.
4. Existing cluster state must prevent reinitialization on rerun. Express this as
   **conditional execution** — a `creates:` guard or a stat-based skip on the
   datastore directory — not as an `assert` (house rule 4). This is the most
   destructive failure available in this phase: a second `cluster-init` against a
   live cluster.
5. Keep the server agent enabled so every server runs workloads. Do **not** add a
   control-plane `NoSchedule` taint. Add both Kubernetes role labels and check
   that an ordinary pod schedules on every node.
6. Configure private node/advertise addresses, the pod and service CIDRs, API
   endpoint TLS SANs and secrets encryption at rest. The SAN list must include
   `kubernetes.api_endpoint` **and** every node's public and private address.
   `api_endpoint` resolves to the entry node only, but the other addresses must be
   valid SANs so `kubectl --server https://<other-node>:6443` works when the entry
   node is down. That is the break-glass path for the API.
7. Disable bundled Traefik — it is installed from its own chart in step 19, so the
   version is pinned and the values are ours. Disable ServiceLB too: with a single
   entry node the host-port binding belongs in Traefik's own chart values, where it
   is visible, rather than being implied by a `type: LoadBalancer` Service and a
   second controller.
8. Store the server token outside Git and outside the JSON. It is required to
   recover encrypted bootstrap data, and without it a snapshot is not a backup.

**Done when.** `kubectl get nodes` shows three `Ready` nodes with both role
labels, `kubectl get --raw /readyz` passes, etcd reports three members, a test pod
schedules on each node, and running the playbook a second time changes nothing.
With no preflight, run this against a disposable cluster first.

---

## Step 15 — Local kubeconfig

**Goal.** A working kubeconfig on your machine that does not disturb your existing
contexts.

**Files.** `roles/k3s_kubeconfig/` (new), `.gitignore`.

**Do.** Fetch to an ignored local path with mode `0600`. Retain CA verification.
Replace the loopback server address with the configured reachable API endpoint.
Use an explicit `--kubeconfig`/context for every Helm and kubectl operation from
here on — never write into the user's default context. Document credential
rotation, and make sure admin credentials are never printed (`no_log`).

**Done when.** `kubectl --kubeconfig <path> get nodes` works from your laptop,
your default context is untouched, and no admin credential appears in any playbook
output.

---

## Step 16 — etcd snapshots, off-node backup, and recovery

> **Deferred 2026-09-27.** Not being implemented for now; may return later. What
> this costs is smaller than it looks, and is written up in the log under step 16
> — the short version is that the cluster is reproducible from Terraform, Ansible
> and Helm, so the real exposure is Let's Encrypt rate limits on re-issuing
> certificates, not application data. The rest of this section is kept as the
> specification for whenever it is picked up. **Two live consequences:** the k3s
> token is backed up nowhere, and step 31's restore checks cannot be performed.

**Goal.** Scheduled snapshots, encrypted off-node copies, and a separately invoked
recovery playbook that has actually been tested.

**Why here.** Before any stateful workload exists. A backup path first tested
during an incident is not a backup path.

**Files.** `roles/k3s_etcd_backup/` (new), `playbooks/k3s_restore.yml` (new),
`docs/k3s-recovery.md` (new).

**Do.**
1. Snapshots every six hours, 28 retained locally per server. **Stagger the
   schedule per node** — `0 */6 * * *` fires on all three servers at the same
   instant, so all three take the I/O and the upload hit together, on nodes that
   are also running every workload.
2. Copy off-node into a private encrypted object store with retention. Use k3s's
   native S3 backup where supported; for GCS and Azure Blob write a
   provider-native upload and retention task rather than assuming the S3-only
   configuration covers every provider.
3. Back up the server token separately.
4. Monitor upload failures and snapshot age.
5. The recovery playbook is **explicitly invoked only**. Ordinary deployment must
   never run a cluster reset. Stop servers, restore one member, rebuild membership
   by rejoining the other two, verify API and workloads.
6. Write in the runbook, in plain words, that etcd snapshots do not back up
   PostgreSQL, RabbitMQ or Redis volume contents. Those need their own backups
   (steps 22, 23, 28).

**Done when.** You have restored a disposable cluster from an off-node snapshot
and its workloads came back. Not "the playbook exists" — restored.

---

# Phase 4 — Platform releases via local Helm

## Step 17 — Helm scaffolding and pinned versions

**Goal.** `infrastructure/helm/` exists with a version manifest, and Ansible can
run Helm from `localhost`.

**Files.** `infrastructure/helm/` (new), `playbooks/deploy_k3s.yml` (new),
`infrastructure/ansible/requirements.{yml,txt}`.

**Do.**
1. Create the directory with a version manifest pinning every chart and container
   image. No floating `latest` — check each pin pulls before recording it.
2. All Helm tasks run in plays with `hosts: localhost`, `connection: local`,
   `become: false`, using the step 15 kubeconfig explicitly.
3. Add pinned `kubernetes.core` and Python Kubernetes dependencies to the
   requirements files, and document the local `helm`/`kubectl` setup.
4. Add `helm diff` to the runbook (your R16 decision) so drift is visible before
   applying. With no preflight and no Ansible assertions, `helm diff` is the only
   look-before-you-leap left in the deployment path — treat it as required, not
   optional.

**Note.** `helm lint` and `helm template` in CI are fine under house rule 4 —
that rule covers Terraform and Ansible, not chart linting.

**Done when.** `helm --kubeconfig <path> list` works through an Ansible play on
`localhost`, and `helm lint` runs in CI on the new directory.

---

## Step 18 — Cloud CSI storage

**Goal.** An encrypted, expandable, topology-aware StorageClass — installed before
anything that claims a volume.

**Files.** `infrastructure/helm/` (CSI driver release), Terraform IAM for the node
identity.

**Do.** Install and configure the selected cloud's CSI driver with the identity
permissions it needs. Select an encrypted expandable class with topology-aware
binding as the default. Do **not** rely on k3s local-path volumes: a local-path
PVC is pinned to one node's disk, which is not recoverable when that node dies.

Note the zonal-disk constraint explicitly in the log: pod rescheduling does not
move a zonal disk. In single-zone mode (your R3 decision) this is moot, but it
becomes the dominant constraint the moment the 3-AZ follow-up lands.

**Done when.** A test PVC binds, a pod mounts it, the volume survives pod
deletion, and expansion works.

---

## Step 19 — Traefik

**Files.** `infrastructure/helm/` (Traefik release).

**Do.** Install from the upstream chart binding **host ports 80 and 443**, with an
explicit ingress class name that every later Ingress references.

**Decide: DaemonSet on all three nodes, or pinned to the entry node.** Both work,
because DNS only sends traffic to one address either way.

- **DaemonSet on all three** — every node listens, and failover is a DNS change
  and nothing else. Costs three Traefik pods instead of one, which on 2 GiB nodes
  is roughly 300 MiB of the cluster's headroom rather than 100 MiB.
- **Pinned to the entry node** — one pod, via a `nodeSelector` or affinity on the
  entry node's hostname. Failover then needs the DNS change *and* moving Traefik,
  which means editing the pin and re-applying while the site is down.

I recommend the DaemonSet. The extra memory buys a recovery procedure with one
step instead of three, and step 8's short TTL only helps if nothing else has to
happen first.

Traffic reaches pods on other nodes through normal Service routing, so the UI,
History and Fetcher pods can schedule anywhere regardless of which option you
pick. Nothing else in the cluster is pinned.

**Done when.** An HTTP request to the entry node's address reaches a test backend
through the ingress hostname, and — if you chose the DaemonSet — a request
straight to each other node's address does too.

---

## Step 20 — cert-manager, ClusterIssuers, and the internal CA

**Files.** `infrastructure/helm/` (cert-manager release and issuer manifests).

**Do.**
1. Install cert-manager as its own Helm release from
   `oci://quay.io/jetstack/charts/cert-manager`, including CRDs. Wait for CRDs,
   controllers **and the webhook** to be ready before creating any issuer — this
   is the most common failure in this step, and it presents as an opaque webhook
   error.
2. Create **one** Let's Encrypt ClusterIssuer, against the production ACME
   directory. Decided 2026-09-27: only real certificates are ever wanted, so
   `acme_environment` was removed from the schema rather than left as a field
   with one used value. Going back to staging would be a code change, which is
   the intent.
3. HTTP-01: public DNS and port 80 must route to the solver. That means step 8's
   Cloudflare records applied, `cloudflare.proxied` false, and the entry node
   reachable on 80 from the internet.

   **What issuing straight to production actually risks.** Less than the usual
   warning implies. A misconfigured solver burns the *failed validation* limit,
   five per account per hostname per hour, which clears in an hour. The
   five-duplicate-certificates-per-week limit only counts **successful**
   issuances of an identical name set, so debugging does not consume it. The
   week limit matters when the cluster is rebuilt repeatedly — which, with
   step 16 deferred, is a real possibility: the ACME account key lives only in
   the cluster and has no backup.
4. Allow DNS-01 for private ingress or wildcards, with narrowly scoped DNS
   credentials.
5. Set the application ingress TLS secret and secure UI session cookies. Remove
   the VM edge proxy's independent ACME ownership from this path —
   `roles/edge_proxy/` stays Compose-only.
6. Add a cert-manager **CA issuer** for internal service DNS names (broker and
   cache TLS). Public Let's Encrypt cannot issue for cluster-internal names.
   Distribute the trust bundle to clients and keep the CA key in protected secret
   storage.
7. Apply your R11 decision: `rabbitmq.certificate_days` becomes the cert-manager
   `Certificate` duration here.
8. Preserve issuer account keys across redeployments — losing them re-registers
   with Let's Encrypt and burns rate limit.

**Done when.** The production issuer issues a certificate for the ingress
hostname, a browser trusts the chain, the internal CA issuer signs a test
certificate for a `.svc` name, the ACME account Secret survives a `helm upgrade`,
renewal has been exercised, and ingress survives a node failure.

---

## Step 21 — Secrets into the namespace

**Files.** `roles/resolve_secrets/` (extend), a new Kubernetes secret role.

**Do.** Resolve existing cloud secret identifiers locally using the operator's
cloud identity, then create namespace-scoped Kubernetes Secrets with `no_log`.
Move away from VM-attached secret files and per-service VM identities. Restrict
pod service accounts and RBAC. Ensure no secret value can appear in Helm values or
output. Document rotation.

**Done when.** Every secret the application needs exists in the namespace, no
value appears in any log or `helm get values` output, and rotation is documented.

---

## Step 22 — RabbitMQ

**Files.** `infrastructure/helm/`, version manifest.

**Per decision T1, this is a single broker instance, not three.** The plan's
section 6 specifies three replicas with quorum queues; that is superseded.

**Do.**
1. Select a chart only after checking licensing, image availability without a
   subscription, supported versions, and TLS/existing-secret support. If nothing
   suitable exists, write a small repository-owned chart over supported upstream
   images. Record the source and version in the manifest — this is a completion
   requirement, not a note.
2. **One replica**, a persistent volume, and ordinary durable queues. Do **not**
   configure quorum queues: at one replica they carry the coordination cost of
   replication while tolerating no failure at all. Skip peer discovery and the
   shared Erlang cookie too — there is no cluster to form.
3. Preserve the existing exchange, routing, main/retry/dead-letter topology,
   outbox behaviour, credentials and delivery policies. With classic durable
   queues this is a closer match to the current Compose behaviour than the
   three-replica design would have been, so the retry/dead-letter policies should
   port unchanged. Confirm rather than assume.
4. AMQPS with DNS SANs matching the client Service endpoint, using the step 20
   internal CA.
5. Map `rabbitmq.memory_mb` (768) to Kubernetes requests/limits explicitly (R12).
   This is the one place a translation bug shows up as an OOMKill loop under load
   rather than as an error.
6. Cluster-internal exposure only. Preserve credentials and volumes across
   upgrades — never regenerate passwords on a rerun.
7. The broker's persistent volume is now the only copy of undelivered messages.
   Back it up; etcd snapshots do not cover it (step 16).

**The limitation to write down.** The broker is a single point of failure.
Publishing and consuming stop while the pod reschedules, exactly as Redis does in
step 23. Client reconnection behaviour is therefore load-bearing: test that
publishers and consumers recover on their own after the pod is killed, because
nothing else will cover for them.

**One thing the R3 single-zone decision buys you here.** With all three nodes in
one zone, the broker's zonal persistent disk can reattach when the pod is
rescheduled onto a different node. That is what makes a single instance tolerable.
It stops being true if the 3-AZ follow-up lands, so record it as a constraint on
that follow-up rather than as a property you can rely on forever.

**Done when.** A killed broker pod reschedules, reattaches its volume, and
publishers and consumers reconnect without intervention; the interruption is
measured and written into the log; and a redeploy preserves data and credentials.

---

## Step 23 — Redis

**Files.** `infrastructure/helm/`, version manifest.

**Do.** One persistent standalone instance, using the existing URL-based client
unchanged. Retain authentication, session TTL and key prefix. Use TLS — clients
can now be on another node, so this traffic crosses the network in a way it did
not under Compose. Map `redis.memory_mb` / `redis.maxmemory_mb` to requests and
limits (R12).

**Write down the honest limitation:** sessions are interrupted while Redis
reschedules. k3s control-plane HA does not make a single-instance service
continuously available. Sentinel is a later option that needs client discovery
changes and failover tests — not a replica-count bump.

**Symmetry with step 22.** Both the broker and the cache are now single
instances, so they share one failure mode and one mitigation: a zonal disk that
can reattach within the single zone. Document them together in
`docs/k3s-deployment.md` rather than in two places that will drift.

**Done when.** Sessions persist across a redeploy, TLS is verified end to end, and
the recovery interruption is measured and written into the log.

---

# Phase 5 — Application

## Step 24 — Database migration Job

**Files.** `infrastructure/helm/oilscope/` (Job template), reuse of
`database/migrations/` and `roles/database_migrate/`.

**Do.** Move schema initialization, role/grant setup and existing migrations into
a Kubernetes Job that completes before application rollout. Reuse the existing
migration runner and SQL — this is a repackaging, not a rewrite. Keep privileged
migration credentials separate from runtime secrets. Prevent concurrent runs. Fail
the deployment on error rather than proceeding with a half-migrated schema.

**Done when.** A fresh database is initialized by the Job, a rerun is a no-op, two
concurrent runs cannot both proceed, and a deliberately broken migration fails the
deployment.

---

## Step 25 — Publish and pull from the native registry

**Files.** `.github/workflows/publish-images.yaml`,
`.github/workflows/reusable-build-image.yaml`, node pull-credential configuration,
`infrastructure/helm/oilscope/` image references.

**Do.**
1. Authenticate to the selected cloud via OIDC (step 9's identity), build and
   push Fetcher, History, UI and the migration image, and expose immutable digests.
2. Configure authenticated pulls on every node using a provider-supported kubelet
   credential provider or an explicitly managed, renewable pull secret. **Check
   support for your pinned k3s release** — the credential-provider integrations
   supplied by managed Kubernetes services do not automatically exist on plain VMs.
   This is the highest-risk assumption in the whole registry change, and with no
   preflight it surfaces as `ImagePullBackOff` during a deployment.
3. Grant pull-only access to runtime identities; handle token refresh
   automatically.
4. Deploy by digest, not tag.
5. Remove `GHCR_TOKEN` and the GHCR username/repository requirements from the k3s
   path — schema, examples, Terraform outputs, Helm values, docs.
6. Support authenticated local publishing for operators as well as CI.
7. Third-party platform images and build bases may stay on their upstream sources.
   If they must also come from the native registry, that is explicit mirroring with
   its own digest tracking — a separate piece of work.

**Done when.** A **fresh** node pulls the pinned digests — a cached image hides
broken authentication, so test on a node that has never pulled before — and pulls
still work after credential renewal.

---

## Step 26 — Application chart

**Files.** `infrastructure/helm/oilscope/` (new chart).

**Do.** Deployments, ClusterIP Services, ConfigMaps, secret references, Ingress,
probes, resources and scheduling for History, Fetcher and UI. Reuse the existing
Dockerfiles unchanged.

- Two UI and two History replicas, **after** confirming concurrent consumer
  behaviour is safe.
- **Per decision T3, spread the services across the three nodes — do not run a
  full stack on every node.** These are ordinary Deployments with topology spread
  constraints, never DaemonSets. With Fetcher at one replica plus two UI, two
  History, one broker and one cache, you have seven pods over three nodes; let the
  scheduler place them and use anti-affinity only where co-location actually
  hurts.
- Fetcher stays at **one** replica with a `Recreate` strategy: its process owns the
  schedule and the startup fetch, so a rolling update briefly runs two schedulers.
  Leader election or a separate scheduling design is a prerequisite for scaling it,
  not a tuning knob.
- Kubernetes service DNS for History, RabbitMQ and Redis.
- Port the existing environment-variable contracts and CA mounts exactly.
- Separate dependency readiness from process liveness, so a temporary database or
  broker blip does not cascade into a restart loop.
- Graceful termination for in-flight consumer work; topology spread for the
  replicated workloads.
- Network policies allowing DNS plus required application, database and ACME
  traffic only.

**Done when.** `helm template` and `helm lint` pass in CI, and a Fetcher →
RabbitMQ → History → UI flow works end to end over HTTPS with persisted
observations and sessions.

---

## Step 27 — `managed_database: false`

> **Not implemented, deliberately — 2026-09-29.** The deployment runs on managed
> RDS and the self-hosted branch was judged strictly worse here, not merely
> unbuilt. Instead, `deploy_k3s.yml` refuses to run when `managed_database` is
> false, naming this step. The specification below is kept for whenever it is
> picked up.

**Why it was skipped rather than built.** A single-replica PostgreSQL on the same
three 2 GiB nodes would be worse than RDS on both axes that matter:

- **Durability.** RDS provides `backup_retention_days` automatically. In-cluster
  gives a PVC and nothing else — and with step 16 deferred there is no backup
  machinery at all, so it would be the only durable data in the cluster with no
  copy anywhere.
- **Availability.** Losing the node holding its PVC means downtime until the pod
  reschedules, and the volume is zonal — which only works at all because the
  deployment is single-AZ.

There is no cost saving to offset that at `db.t4g.micro`.

**Do.** If it is picked up later:

1. Disable cloud database creation and deploy PostgreSQL in the cluster with a
   persistent volume and backups, offering applications the **same connection
   contract** — `k3s_urls` points `DATABASE_URL` at the in-cluster Service
   instead of the RDS endpoint, and nothing downstream changes.
2. `postgres:18.6-bookworm` is already pinned in `versions.yml` and verified
   pullable.
3. The migration Job needs a credential from somewhere other than the RDS master
   secret, which will not exist.
4. No fourth VM, and no silent fallback to managed mode.

Treat flipping the boolean on an existing deployment as a data migration and
cutover, documented separately: back up, transfer, verify, and have a rollback.
Never automatically destroy the previous database, purge messages or sessions, or
imply that switching back restores data.

**Done when.** Both modes deploy and pass the step 26 end-to-end test on the same
three-node topology, and `docs/database-modes.md` documents the cutover.

---

## Step 28 — CI

**Goal.** CI catches what it still can, given that Terraform and Ansible carry no
tests of their own.

**Files.** `.github/workflows/pr-validation.yml`.

**Do.**
1. No configuration-validation job. It would only ever see the committed
   examples, never the file an operator applies, so it would report green while
   proving nothing. This was tried and rejected in step 2; do not reintroduce it.
2. `terraform fmt -check -recursive` and `terraform validate` stay. The existing
   `terraform test` line in the workflow currently passes vacuously — the repo has
   no `.tftest.hcl` files and, under house rule 4, never will. **Remove that line**
   rather than leaving a step that can only ever pass.
3. Ansible lint and syntax checks stay. Drop any reference to `roles/*/tests/`.
4. Add `helm lint`, `helm template` and Kubernetes manifest validation
   (`kubeconform` or equivalent) against the pinned release.
5. Python tests under `pytest` are unaffected by house rule 4. Where a guarantee
   can be checked in Python — tag translation, inventory group membership, secret
   redaction — put it there rather than in Ansible.

**Done when.** CI passes on the committed examples, and no workflow step exists
that cannot fail — check every job for the `terraform test` failure mode, where a
step reports success because it found nothing to do.

---

## Step 29 — Monitoring for the cluster

**Files.** `infrastructure/terraform/modules/*/monitoring/`,
`roles/application_monitoring/`.

**Do.** Cover node readiness, etcd health and snapshot age, certificate expiry,
PVC capacity, broker queue depth, Redis persistence and application freshness.
Replace or adapt the Compose- and journald-specific collectors —
`roles/application_monitoring/files/collect.py` reads from a Compose deployment
and will report nothing here.

With no preflight and no assertions anywhere in the deployment path, monitoring is
now the primary way a broken deployment announces itself. Weight this step
accordingly; it is not the tail end of the project.

**Done when.** Each failure mode above produces an alert on the disposable
cluster, and no alert fires in steady state.

---

## Step 30 — Documentation

**Files.** `README.md`, inventory and platform READMEs, `docs/database-modes.md`,
`docs/dns.md`, `docs/secrets.md`, `docs/k3s-deployment.md` (new),
`docs/k3s-recovery.md` (from step 16),
`docs/supported-compose-deployment.md`.

**Do.** Write the exact deployment and rollback commands — after the entry points
exist, not before, so the commands are real. Document local prerequisites, the
break-glass path from your R14 decision, and the Compose deprecation outcome from
your R15 decision. `docs/dns.md` needs its reasoning rewritten for HTTP-01, not
just its addresses updated (step 8).

This step carries more weight than it would otherwise. Under house rule 1 the code
explains nothing on its own, and under rule 4 nothing in Terraform or Ansible
enforces a constraint. Every invariant that used to live in a comment, a
precondition or a preflight check has to live here instead — including the CIDR
overlap rule from step 3, the defaulting pattern from step 5, the firewall matrix
from step 6, and the four conditions dropped from the DNS module in step 8.

**Done when.** Someone who has not read this document can deploy from
`docs/k3s-deployment.md` alone, and every constraint listed above appears in it.

---

## Step 31 — Verification on disposable infrastructure, then cutover

**Goal.** Everything the plan's section 9 lists, verified by hand on throwaway
infrastructure, followed by a controlled migration.

**Why this step is bigger than the plan implies.** With no Terraform tests, no
Ansible assertions and no preflight, this manual pass is the *entire* verification
story for the infrastructure layer. Do not compress it.

**Do.** Verify, in order:

- exactly three `Ready` nodes, both roles each, workloads schedulable on all three;
  three healthy etcd members;
- local Helm can list, install and upgrade using the generated context;
- CI and local publishing both push to the native registry; a **fresh** node pulls
  the pinned digests and keeps pulling after credential renewal, with no GHCR
  credentials present anywhere;
- invalid or unreachable public/private address combinations — check by hand what
  each one does now, since nothing fails before deployment any more, and write the
  observed behaviour into `docs/k3s-deployment.md`;
- no bastion and no workload-specific VM is created; no broker, cache or etcd port
  is publicly reachable — check against the step 6 matrix;
- database initialization and a full Fetcher → RabbitMQ → History → UI flow, with
  persisted observations and sessions;
- production HTTPS valid, and renewal exercised. There is no staging issuer to
  rehearse against — `acme_environment` was removed from the schema, so the first
  attempt is against the production Let's Encrypt rate limits (5 duplicate
  certificates per week). Get DNS and port 80 right before the first apply;
- a redeploy preserves tokens, passwords, PVCs and data, and does not reinitialize
  etcd;
- stopping a **non-entry** node keeps etcd quorum and leaves the website and API
  fully reachable; pods reschedule onto the survivors;
- stopping the **entry** node keeps etcd quorum but takes down the website *and*
  the configured API endpoint, even though the cluster is healthy. Verify the
  documented recovery: `kubectl --server https://<other-node>:6443` still works
  against the surviving SANs, and repointing the two DNS records at another node's
  Elastic IP restores service within the TTL. Time it — that number is this
  design's real availability figure;
  **Messaging and sessions do not survive this untouched** — per decision T1 there
  is one broker and one cache, so stopping the node hosting either interrupts it
  until the pod reschedules and reattaches its disk. Measure both recovery times
  and write the numbers down; they are the deployment's real availability figure,
  not a footnote;
- ~~etcd restore and stateful-service restore both work from off-node backups~~ —
  **not testable.** Step 16 is deferred, so there are no off-node backups to
  restore from. Losing etcd loses the cluster;
- ~~both database modes work, and changing modes requires the documented
  cutover~~ — **not applicable.** Step 27 was not built: the k3s layout has no
  database-role VM, `managed_database` must be `true`, and the deploy playbook
  stops rather than attempting self-hosted mode. There is one mode to verify.

**Then cut over.** This ordering is not negotiable:

1. Inventory the live deployment's data and take backups.
2. Provision the new cluster **alongside** the existing one.
3. Migrate and verify state.
4. Stop duplicate producers.
5. Switch DNS.
6. Retire the old VMs only after verification passes.

**The safety guard is now Terraform state, not a config flag.** The original
plan isolated the two deployments with `deployment_target`; with the Compose
layout deleted from the schema and the modules, that flag is gone and nothing in
the configuration distinguishes "the old deployment" from "the new one".

What protects the running deployment is that it has its **own Terraform state**
and its own revision of this repository. So:

- provision the cluster into a **separate state file or workspace**, never the
  one holding the existing VMs;
- run any operation against the old deployment from the **previous git
  revision**, which still contains the Compose modules;
- do not run `terraform apply` with the new root against the old state. It will
  plan the destruction of every existing workload host, and it will be right to —
  those resources no longer exist in the configuration.

That last point is the single most destructive mistake available in this project.
Check `terraform workspace show` and the configured backend key before every
apply during the cutover window.

**Done when.** The application serves production traffic from the cluster, the old
VMs are gone, and the log's final entry records the real monthly cost against the
step 1 estimate.

### Runbook

Checked against the repository on 2026-10-02, not guessed. Every command assumes
`$ROOT` is the repository root and `$CFG` the absolute path to the real
configuration:

```sh
ROOT=/Users/pavlo/Documents/Projects/Softserve/2
CFG="$ROOT/project-config.new.json"
export AWS_PROFILE=oilscope
```

Observed facts the runbook depends on: the Terraform state is **local**
(`infrastructure/terraform/terraform.tfstate`, no backend block), workspace
`default`. The kubeconfig context is `name_prefix`-`environment` =
`oilscope-prod`, so `~/.kube/oilscope-prod.yaml`.

`project_config_path` already defaults to `../../project-config.new.json`, which
resolves to the repository root whether Terraform runs with
`-chdir=infrastructure/terraform` or from inside that directory. So **pass no
`-var` at all** and make sure `TF_VAR_project_config_path` is unset. An
environment variable pointing at an older copy of the configuration is the most
dangerous thing in this procedure: against live state it plans the destruction of
every node, because those nodes do not appear in that file. A saved plan file
refuses the override and warns, but a bare `plan` or `apply` does not.

Two CLI details that cost a round trip each:

- `terraform import` takes its flags **before** ADDR and ID. Flag parsing stops
  at the first positional argument, so a trailing `-var` is read as two more
  positionals and the command fails with "Wrong number of arguments".
- `aws` needs `AWS_PROFILE=oilscope` explicitly. The default profile on this
  machine has an invalid token. Terraform is unaffected, because the provider
  block pins the profile.

#### Phase A — unblock the plan (31.1–31.3)

- **31.1 Clear the two plan-blocking errors.** Done 2026-10-02. A plan ended in
  exactly two fatal errors: `modules/azure/network/locals.tf:27` read
  `network.management_subnet_cidr`, which the schema no longer has, and the
  Cloudflare provider had no token. Resolved by exporting
  `CLOUDFLARE_API_TOKEN` and by **commenting out** the six `module "azure_*"`
  blocks in `main.tf` with the outputs reading them in `outputs.tf` — no file
  under `modules/azure/` was touched. See the note below on what that also fixed.
- **31.2 Confirm the identity and the state file.** `aws sts get-caller-identity`,
  `terraform workspace show`, and a resource count from the state. Zero resources
  means nothing can be destroyed by an apply, which is the one piece of luck here.
- **31.3 Validate the configuration by hand.** Nothing does this for you:
  `uvx check-jsonschema --schemafile infrastructure/terraform/project-config.schema.json "$CFG"`,
  then the four unenforceable rules in `docs/k3s-deployment.md` by eye.

#### Phase B — infrastructure (31.4–31.6)

- **31.4 Read the plan.** `terraform plan` to a saved file; confirm the resource
  count and that no module path under `modules/gcp/` or `modules/azure/` appears
  in the create list.
- **31.5 Apply.** Costs money from this point.
- **31.5b Recover deleted secret names, if the apply hit them.** Secrets Manager
  reserves a deleted name for its whole recovery window, so `CreateSecret` is
  refused rather than reusing it. Restore and adopt rather than purge — the
  deleted versions still hold real values, including the OilPriceAPI key.
- **31.6 Export the outputs.** Ansible reads a JSON export, not the state. A stale
  export silently feeds old addresses to every later step.

#### Phase C — the cluster (31.7–31.10)

- **31.7 Confirm the inventory sees three hosts** before bootstrapping anything.
- **31.8 Bootstrap k3s.** The entry node initialises the cluster; the other two
  join `serial: 1`.
- **31.9 Verify three `Ready` nodes, both roles each, and three etcd members.**
- **31.10 Verify the kubeconfig and that pods schedule on all three nodes.**

#### Phase D — images (31.11–31.13)

- **31.11 Publish.** `git tag pavlo-v1.0.0 && git push origin pavlo-v1.0.0`; the
  workflow prints four digests in its job summary.
- **31.12 Record the digests** in `registry.image_digests`
  (`fetcher`/`history`/`ui`/`database`), then **re-apply and re-export** —
  the image references are built from them.
- **31.13 Verify a pull with no GHCR credentials anywhere**, and that it still
  works after the ECR token's 12-hour expiry — that is what the registry
  CronJob exists for, and the `JobsFailed` alarm is its only signal.

#### Phase E — platform and application (31.14–31.17)

- **31.14 Deploy.** `deploy_k3s` installs the CSI driver, Traefik, cert-manager,
  RabbitMQ, Redis and the application, in that order.
- **31.15 Watch certificate issuance.** This is the **first and only** attempt
  against production Let's Encrypt; there is no staging issuer to rehearse with.
- **31.16 Verify HTTPS and the full flow** Fetcher → RabbitMQ → History → UI,
  with persisted observations and a session that survives a reload.
- **31.17 Re-run the deploy unchanged.** It must preserve tokens, passwords, PVCs
  and data, and must not reinitialise etcd.

#### Phase F — measure what the design actually costs (31.18–31.21)

These produce the deployment's real availability numbers. Write each one down.

- **31.18 Stop a non-entry node.** Expect: etcd quorum held, website and API fully
  reachable, pods rescheduled.
- **31.19 Stop the entry node.** Expect: cluster healthy, website *and* API
  endpoint down. Verify `kubectl --server https://<other-node>:6443` still works.
- **31.20 Time the manual failover** — repoint both A records at another node's
  Elastic IP and measure to first successful request.
- **31.21 Time RabbitMQ and Redis recovery separately.** One replica each, so
  whichever node hosted them has an outage of its own: pod reschedule plus EBS
  volume reattach.

#### Phase G — the firewall (31.22)

- **31.22 Scan from outside** and compare against the matrix in
  `docs/k3s-deployment.md`. No broker, cache, etcd or kubelet port may answer
  from a non-admin address.

#### Phase H — cutover (31.23–31.26)

Only meaningful if a live deployment exists; this state file holds nothing, so
confirm first whether the old deployment is still running and from which state.

- **31.23 Back up the live deployment's data** and inventory what exists.
- **31.24 Migrate and verify state** with both deployments running.
- **31.25 Stop duplicate producers, then switch DNS.**
- **31.26 Retire the old VMs** only after verification passes, from the **previous
  git revision** that still contains the Compose modules.

#### What 31.1 also fixed

Commenting out the Azure module blocks removed the Azure credential requirement
that this repository had documented as a deliberate, permanent cost. A provider
with no resource referring to it is never configured, so no authorizer is built.
An AWS plan now needs `AWS_PROFILE` and `CLOUDFLARE_API_TOKEN`, and nothing else.

Verified by planning with `AZURE_CONFIG_DIR` and `CLOUDSDK_CONFIG` pointed at
empty directories and no `ARM_*` or `GOOGLE_*` set: no provider error from either
cloud. The earlier conclusion that this could not be fixed was drawn from a
different experiment — a `count = 0` module that still *contained* an azurerm
resource, which does demand credentials. Removing the module call is not the same
thing as zeroing its count, and only the former works.

Three options were weighed before this one was chosen:

| Option | Cost |
| --- | --- |
| **Comment out the module calls** (chosen) | Root-level edit only. Azure and GCP credentials both stop being required. Breaks the Azure Compose path further, which was already unrunnable under the k3s schema. |
| `try(...)` in the Azure locals | One line in a module that is off-limits, and it would have left the credential requirement in place. |
| Add `management_subnet_cidr` back to the configuration | No module edit, but it reintroduces the orphaned CIDR from R4 and `network` has `additionalProperties: false`, so the 31.3 schema check would then fail. |

Uncommenting is one operation across both `main.tf` and `outputs.tf`. Expect
`modules/azure/network/locals.tf` to fail immediately on the removed key: a
`locals` block is evaluated whatever value `count` takes, which is why narrowing
that module's `enabled` had no effect.

---

## Deployment inputs still needed

The steps above can all be implemented with placeholders. A real deployment needs:
the selected cloud, account and region; application and API DNS names; the ACME
email; administrator CIDRs; the SSH identity; native registry names and the
publishing and pulling identities; and the existing secret references. Default to
managed PostgreSQL. There are no load balancers: both hostnames resolve to the
single `kubernetes.entry_node` address. All three nodes still need public
addresses — for administration, for outbound access, and so ingress can be moved
to another node by hand — but only one of them receives user traffic.
