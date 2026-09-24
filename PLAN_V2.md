# Azure implementation plan — V2

Date: 2026-09-21. Revised against `PLAN_REVIEW.md` and the user-supplied follow-up review (`pasted-text.txt`, attachment `f58e1f22-27ec-44f5-b79b-b37f4a5fae5e`). Scope: design only. No production implementation, provisioning, deployment, or automated test suite was performed. One provider-free Terraform console diagnostic verified expression typing in a temporary directory; this revision edits only this plan.

## 1. Authority, readiness, and boundaries

**Specification: `azure.md`**, as clarified by the supplied review.  D0 is removed and remaining decision IDs are preserved for traceability. This plan is a complete implementation design, but it is **not yet ready for unconditional implementation**: D12’s technical diagnostic is resolved for the reviewer-tested AzureRM v4.63 graph, but approval of the recommended separate Azure root remains a critical pre-T1 architecture gate, and the other decision gates below remain unapproved. Review recommendations are evidence to assess, not blanket approval to change requirements. Section 15 records accepted and corrected review findings.

Changes in V2 include exact configuration limits, Azure inventory option semantics, explicit secret/migration failure handling, example-only address corrections, cross-platform lockfile requirements, and a narrower live-validation gate. V2 retains the object-valued Azure image contract: review H1’s asserted Terraform type error was disproved by a provider-free expression diagnostic. The follow-up review supplies empirical evidence against the placeholder-subscription remedy (§15.2). This revision recommends root isolation, subject to explicit approval of the specification exception, and retains the rejection of a vault-wide secret-read fallback.

The investigation covers root Terraform, AWS/GCP network/VM/database/secrets/monitoring/budget modules, Cloudflare DNS, configuration examples/schema, inventory plugins/helpers, deployment/preflight and cloud-aware roles, collector, relevant documentation, CI, and the prior database handoff. The latter contains historic deployment permissions and progress; neither grants new permission nor proves current runtime health.

Preserve the requested implementation boundary: no changes to `services/`, `database/`, or Docker images; no unrelated refactoring. Infrastructure-owned Ansible templates and `roles/application_monitoring/files/collect.py` are within the proposed scope. Preserve RabbitMQ, Redis, mandatory `managed_database`, and mode-switch semantics. Do not add automated tests. The prior handoff additionally says not to run tests without a new request; the validation plan distinguishes static checks and manual observations from automated suites.

Mandatory sequencing from `azure.md`: complete and review **all Phase 1 Terraform work and its output contract before starting Phase 2 Ansible implementation**. Planning both phases now is necessary to establish that contract. Live Azure apply and end-to-end deployment require separate authorization; this plan grants none.

## 2. Current architecture findings

### 2.1 Configuration and Terraform graph

- `infrastructure/terraform/locals.tf` loads one JSON file and merges monitoring defaults, including nested synthetics defaults. No JSON Schema validation is invoked by Terraform. `variables.tf` checks file existence, with a workstation-specific default path. Always supply an explicit path during validation; do not inadvertently operate on the real Desktop deployment.
- `main.tf` declares the AWS/GCP modules unconditionally. Resources gate themselves through filtered `for_each`, `count`, and `enabled` locals. Budget modules take `name`/`settings`, not `config`; GCP budget additionally takes `project_id`. Monitoring takes `config`, `vms`, and managed-database metadata. There is no generic cloud-module interface enforced across all components.
- VM and network modules honor `vm.cloud` before `default_cloud`. Database modules select **only** `default_cloud` plus `managed_database == true`. This can describe a mixed topology Terraform can partially construct but Ansible refuses to deploy.
- Existing AWS/GCP VM locals resolve size/image/disk mappings for all VMs before filtering by provider. These brace-delimited comprehensions produce **objects**, whose attributes may have different types; they do not impose the homogeneous-value requirement of `tomap` or `map(T)`. Keep Azure images as strict publisher/offer/sku/version objects and split the image JSON schema. Do not add `tomap`, a shared `map(string)` image constraint, or mixed-type conditional branches; resolve only selected Azure VMs in the new module. Existing eager lookups still require valid mappings for every selected VM.
- Unselected providers are not universally isolated. `providers.tf` unconditionally indexes AWS/GCP region branches; AWS network/monitoring locals also read AWS region data. GCP monitoring directly reads `budgets.gcp.enabled`. Those runtime dependencies belong to the existing root. The proposed Azure root must not instantiate these AWS/GCP modules or providers. Shared-schema-required AWS/GCP mappings still remain in examples; do not confuse schema requirements with Azure runtime dependencies.
- Budgets can run without workload VMs or enabled monitoring. Explicit `monitoring.synthetics.clouds` can run probes in another cloud. Thus resource activation is not simply `default_cloud == provider`.
- Current version constraints: Terraform `~> 1.15.1`, Google `~> 7.44.0`, AWS `~> 6.63`, random `~> 3.7`, archive `~> 2.7`, Cloudflare `~> 5.12`. Preserve these; do not perform a blanket provider upgrade while adding Azure.

### 2.2 AWS and GCP behavior

| Component | AWS implementation | GCP implementation |
| --- | --- | --- |
| Network | VPC, management/workload subnets, Internet Gateway, paid NAT Gateway and private routes; second-AZ RDS subnet in cloud mode | Custom VPC, management/workload subnetworks, Cloud Router/NAT, private Google access; private services access allocation/peering in cloud mode |
| Placement | Bastion **and UI** use management subnet | Only bastion uses management subnet; UI uses workload subnet even with public IP |
| VM | AMI resolved through SSM parameter; IAM role/profile per VM; cloud-init provisions SSH users; EIP where requested | Compute instance plus per-VM service account; metadata SSH keys; static external address where requested; shielded VM settings |
| Firewall | Role security groups; SSH from bastion; History API from UI; PostgreSQL from Fetcher/History; RabbitMQ TLS from Fetcher/History | Network tags (`infra` means database); equivalent ingress relationships; managed SQL restricted by source-side allow/deny egress rules |
| Runtime secrets | Value-free Secrets Manager containers; instance-role reads scoped to mapped ARNs | Value-free Secret Manager containers; per-secret service-account grants; optional controller version-adder grants |
| Managed DB | Private RDS, managed master-password secret, enforced SSL, explicit JSON profile | Private Cloud SQL, shared CA, provider DNS-name selection, private DNS records; generated password written to SQL and Secret Manager |
| DB lifecycle | Deletion protection off; no final snapshot; automated backups deleted | Deletion protection off; no retained/final backup; child DB/user abandon policy permits containing-instance destruction |
| Monitoring | CloudWatch native and guest metrics, agent/EMF logs, alarms, dashboards, SNS, Synthetics with optional browser journey | Ops Agent logging/guest metrics, custom Monitoring API metrics, alerts/dashboard, uptime check; no native browser journey |

Source files: `modules/{aws,gcp}/{network,vm,secrets,database,monitoring,budget}/`; consult `network/locals.tf`, `vm/locals.tf`, `database/{main,outputs}.tf`, and `monitoring/{locals,agent,application}.tf` for the distinctions above.

Both examples use a management `10.0.0.0/29`, workload `10.0.1.0/26`, bastion `10.0.0.2`, History `10.0.1.3`, and 10 GiB OS disks; application mode also uses `infra` (database) at `10.0.1.2`. The UI example address is in the workload range, conflicting with current AWS management-subnet placement. These are existing configuration problems, not evidence Azure must replicate the AWS placement. Azure reserves the first four and final subnet addresses, making the example bastion/History IPs invalid. AWS also reserves those addresses and does not permit the example management `/29`; see §15.4. The application example’s database address is also reserved. Image minimum OS-disk size may exceed the configured 10 GiB; verify the exact image before choosing it. These constraints prevent a blanket claim that switching only `default_cloud` makes the examples deployable. Reserved IPs and subnet/IP mismatches may survive plan and fail only at Azure/AWS API creation; they are not proof that a baseline plan is unobtainable.

The **local, untracked** `TF/terraform.tfstate` records management/workload subnets at `10.10.0.0/24` and `10.10.1.0/24`, with bastion `.0.10`, History `.1.11`, Fetcher `.1.12`, and UI `.0.13`. Only network/IP attributes were inspected; secret-bearing state content was not printed. This supports an **example-file-only** address repair, not a live address migration or a claim of current cloud health. Contrary to the review, state is not tracked (`git ls-files` lists the lockfile but not state). UI placement still differs between providers and remains a separate D2 issue.

### 2.3 What is genuinely cloud-neutral

- Application roles, workload keys, abstract size/image/disk/region keys, service ports, registry, RabbitMQ/Redis settings and secret *environment-variable names* are reusable.
- `database_connection` produces the same application environment regardless of managed provider. Compose services consume host/port/database/user/password/TLS inputs rather than cloud SDKs.
- Managed migrations run the same image and SQL from History. Admin and runtime credentials are separate; runtime usernames are `oil_tracker_<vm-key>`.
- Collection probes are neutral (`collect(config)`); `publish(config, metrics)` is AWS/GCP-specific.
- Inventory path/name helpers, effective-cloud calculation, expected-host validation, and SSH proxying are reusable. The default SSH key remains GCP-specific (`~/.ssh/google_compute_engine`); Azure operators must explicitly set `OILSCOPE_SSH_KEY` and choose a provisioned user.
- `network_tags` is nominally in the neutral VM schema but has GCP-specific semantics. Azure should use role relationships and native NSGs/ASGs. `network_tags` must still be populated because the shared schema requires it (including bastion/UI `contains` rules), although Azure ignores it. Removing that requirement is outside scope.
- Monitoring flags are an intent interface, not a fully neutral service contract: retention enum reflects CloudWatch, synthetic runtime is AWS-specific, detailed monitoring is EC2-specific, and browser journeys exist only on AWS.

### 2.4 Ansible execution and identities

`plugins/inventory/oilscope_aws.py` wraps `amazon.aws.aws_ec2`; `oilscope_gcp.py` wraps `google.cloud.gcp_compute`. Each generates delegate settings from JSON, filters by project/environment and region/zone, derives VM key from the cloud resource name, groups by role, and applies helper validation/SSH settings. All non-bastion SSH goes through bastion, including publicly addressed UI hosts.

`playbooks/tasks/preflight_checks.yml` independently rejects mixed clouds, missing/empty inventory, inconsistent role/cloud, duplicate VM keys, and missing role/workload group membership. This duplication is deliberate: inventory parse errors can leave partially added hosts accessible. `deploy.sh` separately rejects a wholly empty `--limit` selection. Preserve both defenses.

Deployment import order is `database.yml` → `migrate.yml` → `rabbitmq.yml` → `history.yml` → `fetcher.yml` → `ui.yml` (Redis inside UI deployment). Cloud mode avoids the local database play by having no database inventory group; `database.yml` does not explicitly inspect database mode. Migration is skipped in application mode. `migrate.yml` targets all History hosts despite a task title mentioning a primary host; multiple History VMs would cause concurrent migration attempts. The supported examples have one History VM.

Runtime secret reads execute **on the VM**: AWS CLI with instance credentials; GCP metadata token then Secret Manager REST. Secret uploads execute **on the controller**. Managed admin and runtime password retrieval for SQL bootstrap also executes on the controller; values are passed transiently to migration commands on History. Do not grant database-admin access to History's managed identity to make migration convenient.

### 2.5 Existing Terraform → Ansible contracts

| Producer / contract | Consumer / interpretation | Azure requirement |
| --- | --- | --- |
| Full `terraform output -json` file | `terraform_outputs_path`; entries have `{value, type, sensitive}` wrappers | Preserve wrapped export format; do not substitute `terraform show -json` or a raw module object |
| `<cloud>_database_connection.value` | `database_connection/tasks/main.yml`, selected by config `default_cloud` | Nullable outside Azure cloud DB mode; usable DNS host, fixed port, DB name, admin identity/reference, verified trust metadata |
| `admin_secret_arn` (AWS), `admin_secret_id` (GCP) | `database_migrate/tasks/main.yml` and `read_secret.yml`; secret JSON includes `password` | Add explicit Azure selection; preserve legacy fields and parsing |
| `<cloud>_monitoring.value.agent_configurations[vm_key]` | `monitoring_agent/tasks/main.yml`; key presence enables agent | Azure-specific typed payload allowed; absent key disables; `{}` when inactive |
| `<cloud>_monitoring.value.collector_configurations[vm_key]` | `application_monitoring/tasks/main.yml`; merged with role, History port, RabbitMQ queue/vhost | Supply Azure publication metadata without tokens/keys |
| VM names, static/private/public IPs, role/name labels from Terraform-created resources | Dynamic cloud discovery, then `hostvars`/role groups | Inventory reads Azure APIs, **not** `workload_*` Terraform outputs |
| Config `secret_mappings` and created grants | Secret resolver and controller uploader | Stable logical IDs, explicit mapping to actual Azure secret URI/name |
| Root `secret_ids`, `secret_resource_names`, `workload_secret_access` | Primarily operator inspection today, not current resolver input | Extend additively; make new Azure URI contract explicit if consumed by roles |

Root `vm_names`, `vm_internal_ips`, `vm_public_ips` are **locals**, not public outputs. Public outputs are `bastion_public_ip`, `workload_vm_names`, `workload_roles`, `workload_internal_ips`, `workload_external_ips`, plus GCP-specific `workload_network_tags` and `workload_service_account_emails`. Outputs are consumed by named fields, not positionally. AWS/GCP monitoring payloads differ except for the agent/collector maps. Do not invent Azure equivalents of SNS ARNs or GCP service-account emails.

## 3. Current documentation checks and design corrections

V1 documentation was fetched through Context7 (library resolution followed by Key Vault and Flexible Server lookups; three CLI calls for that investigation). V2 adds provider-configuration verification and the evidence in §15. Additional precise checks used primary AzureRM, Microsoft and Ansible sources. Provider `main` and collection `dev` documentation are moving references, **not a selected release**; the implementation must select a released version and verify its tagged schema before freezing arguments. A latest-release API lookup was unavailable, so no numeric AzureRM/collection pin is asserted here.

| Verified behavior | Design implication and source |
| --- | --- |
| Key Vault secret needs `value` or `value_wo`; updates create versions | No equivalent value-free container resource. Workload secret lifecycle needs D4; placeholder values are not an acceptable unapproved substitute. [AzureRM secret](https://github.com/hashicorp/terraform-provider-azurerm/blob/main/website/docs/r/key_vault_secret.html.markdown) |
| Azure reserves five addresses per subnet | Example static IPs cannot be carried over unchanged. [Azure networking FAQ](https://learn.microsoft.com/en-us/azure/virtual-network/virtual-networks-faq) |
| Flexible Server VNet integration needs dedicated delegated subnet, private DNS, public access disabled; backup retention 7–35 days; current docs include PG18 and write-only password fields | Do not copy RDS one-day backup profile. Wait for DNS link readiness. Validate release support and target-region SKU/version, not just resource spelling. [Flexible Server resource](https://github.com/hashicorp/terraform-provider-azurerm/blob/main/website/docs/r/postgresql_flexible_server.html.markdown) |
| AzureRM requires subscription for plan/apply, though not validate | Zero Azure resources does not establish zero Azure authentication requirements. The follow-up reviewer demonstrated authentication for zero-instance resource/module graphs under v4.63 (§15.2); use root isolation subject to D12 approval. Provider registration behavior also varies by release. [Provider documentation](https://github.com/hashicorp/terraform-provider-azurerm/blob/main/website/docs/index.html.markdown) |
| Role NSGs and subnet associations have different cardinality than AWS SGs | A shared workload subnet cannot carry five role NSGs as independent subnet associations. Use NIC-associated role NSGs, optionally ASGs for source-role identity; deny otherwise allowed VNet traffic explicitly. [NSG resource](https://github.com/hashicorp/terraform-provider-azurerm/blob/main/website/docs/r/network_security_group.html.markdown) |
| AMA on Azure VMs is a VM extension with managed identity and DCR association | It is not an Ops Agent YAML file installed by a shell script. Pick one owner for extension/DCR lifecycle. [AMA management](https://learn.microsoft.com/en-us/azure/azure-monitor/agents/azure-monitor-agent-manage) |
| Current AMA supported OS matrix includes Ubuntu 26.04 | No basis for silently downgrading the shared image key. Marketplace availability, image minimum disk and chosen agent release still need exact checks. [AMA OS support](https://learn.microsoft.com/en-us/azure/azure-monitor/agents/azure-monitor-agent-supported-operating-systems) |
| Current DCR docs expose `log_file` format `text` or `json`; custom JSON ingestion goes to custom Log Analytics tables | Reuse the collector probes, emit flat JSONL, create table/schema/transforms; Azure Monitor metric alerts alone cannot cover log-derived signals. Establish support in the selected release before adding AzAPI. [DCR resource](https://github.com/hashicorp/terraform-provider-azurerm/blob/main/website/docs/r/monitor_data_collection_rule.html.markdown), [JSON collection](https://learn.microsoft.com/en-us/azure/azure-monitor/vm/data-collection-log-json) |
| Log Analytics workspace retention accepts 30–730 days | Existing default 7 and much of the neutral enum cannot map directly; do not silently clamp. [Workspace resource](https://github.com/hashicorp/terraform-provider-azurerm/blob/main/website/docs/r/log_analytics_workspace.html.markdown) |
| Standard availability tests accept 300/600/900-second frequency and text matching, not browser journeys | Shared 30/60-minute intervals and JSON-status/browser semantics need explicit support limits or a custom runner. [Standard web test](https://github.com/hashicorp/terraform-provider-azurerm/blob/main/website/docs/r/application_insights_standard_web_test.html.markdown) |
| Budget requires time period/start date and notifications; the resource has no configurable currency argument | Add an explicit stable first-of-month start date; preserve logical currency only as a billing-currency assertion. Convert absolute spend thresholds to percentage values. [RG budget](https://github.com/hashicorp/terraform-provider-azurerm/blob/main/website/docs/r/consumption_budget_resource_group.html.markdown) |
| Azure PostgreSQL currently identifies DigiCert Global Root G2 and Microsoft RSA Root CA 2017 as trust roots | Do not invent a single Azure bundle URL or pin a leaf/intermediate. Assemble/maintain an approved root bundle or use an approved system bundle contract. Keep libpq `verify-full`, not alternative spellings found in examples. [Azure PostgreSQL TLS](https://learn.microsoft.com/en-us/azure/postgresql/security/security-tls) |
| Azure inventory provides its own host naming/filtering/auth options; current collection dev floor is Ansible 2.16 | Use raw VM `name`/tags, never decorated inventory name; current repo floor 2.17 need not rise automatically. Validate the selected release and Python 3.14 CI compatibility. [Inventory](https://docs.ansible.com/projects/ansible/latest/collections/azure/azcollection/azure_rm_inventory.html), [runtime metadata](https://github.com/ansible-collections/azure/blob/dev/meta/runtime.yml) |

Other corrections to `azure.md`:

1. In its Phase 1 acceptance sentence, only the clause “application … forbids database-role VMs” is inverted; application mode correctly creates no managed server. Current schema and prior decisions require a database-role VM in application mode and forbid one in cloud mode. Record the corrected clause as “application creates no managed server and requires a database-role VM”; confirm the specification correction rather than implementing the typo.
2. “No fallback values except monitoring” is not a description of all existing code: typed Cloudflare configuration and budget modules have defaults, and provider-specific locals have `try` fallbacks. Apply strict selected Azure infrastructure values without rewriting existing defaults or claiming full global compliance.
3. “Each module needs an explicit source because sources are not inherited” overstates the necessity for the default `hashicorp` namespace. Explicit requirements remain a good choice and are essential for nondefault provider namespaces; add Azure requirements consistently without unrelated AWS/GCP rewrites.
4. Follow the six Azure module boundaries and the requested conventional files. Topic-file names below identify responsibilities, not additional module boundaries; split monitoring/network topics where useful and avoid empty boilerplate files.
5. The schema reuses `$defs/per_cloud_string` for size, disk **and image**. Split the image definition before adding Azure’s publisher/offer/sku/version object; otherwise unrelated maps accidentally accept image objects. A URN is an optional encoding change, not a required fix: review H1 incorrectly equates an object comprehension with a homogeneous map. Preserve the task’s structured image representation; do not substitute a Ubuntu 24.04 URN under the existing Ubuntu 26.04 key.
6. Adding Azure as required in every map would reject old AWS/GCP JSON. Require Azure branches when selected (and whenever independent Azure features need them), not universally, unless a breaking schema migration is explicitly approved.
7. Networking lacks resource-group ownership, NSG default-rule handling, reserved-address checks, first-boot SSH, NAT costs and controller data-plane reachability decisions. These are prerequisites, not cosmetic details.
8. IAM principal ID, client ID, ARM identity ID, vault ARM secret scope, and HTTPS secret URI are distinct values. They cannot share one ambiguous `id` field.
9. “No passwords in outputs” is weaker than “no passwords in Terraform state.” GCP already stores admin password material in state. Azure admin lifecycle needs its own explicit decision; `sensitive=true` is not encryption or omission.
10. AWS/GCP parity means matching observable behavior, not replacing every service with its nearest Azure name. Native availability checks do not reproduce AWS's browser interaction or GCP's JSON-path status predicate.
11. The same-root provider/module/output changes in §1.4 items 2, 4 and 5 conflict with credential-free legacy-plan compatibility for the tested AzureRM graph. D12 recommends an explicitly approved exception placing these changes in a separate Azure root; the six module boundaries and shared Ansible contract remain.

## 4. Requirement-to-code impact and cloud-enumeration audit

Paths below are relative to the repository. `TF` means `infrastructure/terraform`; `COL` means `infrastructure/ansible/oilscope/platform`.

| Requirement / branch | Files and necessary impact |
| --- | --- |
| Cloud selection and strict Azure branches | `TF/project-config.schema.json`: cloud enum; per-cloud size/disk maps; new image definition; region entry; clouds; database profile; budgets; synthetics clouds; conditional selected-cloud/DB requirements. Both `project-config*.json` examples. Preserve VM definitions except D2-approved corrections. |
| Resource graph/provider | Subject to D12 approval, add `TF/azure/{main,locals,variables,providers,versions,outputs}.tf` and its own `.terraform.lock.hcl`; add `TF/modules/azure/{network,vm,secrets,database,monitoring,budget}`. Preserve the legacy provider/resource graph, state addresses and lockfile. Do not add Azure module references to the legacy root. |
| All Terraform cloud selectors | Existing `{aws,gcp}/vm/locals.tf`, `{aws,gcp}/network/locals.tf`, `{aws,gcp}/secrets/locals.tf`, `{aws,gcp}/database/locals.tf`, `{aws,gcp}/monitoring/locals.tf`; existing branches remain provider-specific. Preserve heterogeneous object locals (see §15 H1), inspect inactive lookups, and change existing code only for a demonstrated integration failure. No AWS/GCP image-local rewrite is required solely for the new object representation. |
| Root operator contracts | New `TF/azure/outputs.tf` exposes the existing consumer contract plus Azure metadata. Preserve legacy output values/contracts, allowing blocking preconditions only if needed for the mandatory wrong-entrypoint guard; represent inactive old-cloud fields with contract-compatible literals in the Azure root, never references to AWS/GCP modules. |
| DNS explicit cloud map | `TF/modules/cloudflare/dns/{variables,main}.tf`: `azure_vms` optional empty input **and** Azure `public_ips` map entry. Missing map entries currently fall through to `coalesce("", "")`, which errors before the intended address precondition. Cover that failure explicitly; do not merely add the input variable. Preserve one-UI ingress; the current `proxied` comment refers to a missing validation, so do not claim the existing code enforces it. |
| Inventory/SSH | New `COL/plugins/inventory/oilscope_azure.py` and `infrastructure/ansible/inventory/oilscope-azure.yml`; shared `COL/plugins/module_utils/oilscope_inventory.py` comments and any necessary Azure validation; preserve helper behavior for old clouds. |
| Runtime secrets | `COL/roles/resolve_secrets/tasks/{main,azure}.yml`; defaults/meta/README as required; expand explicit `['gcp','aws']` guard and error text. |
| Controller uploads | `COL/roles/secret_versions/tasks/{main,azure}.yml`; current `main.yml` dispatches only AWS/GCP and has no final unknown-cloud guard—add one. Existing `put_secret_version.yml` is AWS-specific, not a reusable universal uploader. |
| Managed migration | `COL/roles/database_migrate/tasks/{main,read_secret,runtime}.yml`: replace AWS-versus-else-GCP assumptions, support admin URI and logical runtime IDs, decode exactly once, scrub Azure facts in `always`. |
| Trust material | `COL/roles/database_connection/tasks/main.yml` and vars/README if D8 changes bundle contract; existing templates keep the same mounted PEM path/checksum behavior. |
| Agent lifecycle | `COL/roles/monitoring_agent/tasks/{main,azure}.yml`; existing disable-path/service ternaries treat every non-AWS cloud as GCP; fix explicit dispatch including removal/disabled behavior. Review handlers/defaults/meta/README. |
| Collector/logs | `COL/roles/application_monitoring/tasks/main.yml` AWS-only service-log links; `files/collect.py` explicit AWS/GCP publishers; rotation/systemd files if Azure path changes. Reuse neutral probes and metric catalog `infrastructure/terraform/monitoring-metrics.json`. |
| Dependency enumeration | `infrastructure/ansible/{requirements.yml,requirements.txt}`, `COL/galaxy.yml` dependencies/tags, `COL/meta/runtime.yml`; role metadata for resolver/uploader/agent. Existing requirements are lower bounds, not exact pins. |
| Deployment safety | `COL/playbooks/tasks/preflight_checks.yml`, `COL/playbooks/{preflight,deploy_workloads,migrate,bootstrap_bastion}.yml`, `infrastructure/ansible/deploy.sh`; cloud-neutral checks should remain, including mixed-cloud rejection unless D3 changes scope. No Azure-specific new deployment order. |
| Documentation and examples | `README.md`, `docs/{database-modes,monitoring,secrets,dns}.md`, inventory README; collection README/CHANGELOG/plugins README; affected role READMEs/default comments; new module documentation. Existing AWS/GCP-specific documentation remains valid. |
| CI and existing fixtures | `.github/workflows/pr-validation.yml`, `.github/workflows/security.yml`, `.pre-commit-config.yaml`, lint configuration; legacy AWS/GCP role fixtures and monitoring tests contain cloud enumerations. Explicitly initialize/validate both Terraform roots in CI; recursive formatting alone does not validate the nested root. No new tests/fixture rewrites by default; do not replace intentional provider-specific examples globally. |

A repository-wide case-insensitive AWS/GCP search was performed across tracked-style source/documentation paths, followed by hidden CI/config paths. Most occurrences under `modules/aws` and `modules/gcp` should **not** gain Azure branches. Operational shared branches requiring attention are those enumerated above. `roles/history/defaults/main.yml` and role/readme comments also mention GCP/AWS but do not select infrastructure providers. The prior database handoff contains historical provider/deployment facts; preserve that history rather than treating every occurrence as code to change.

## 5. Terraform implementation phases

Each phase is conditional on the decisions cited. File layouts are proposals, not approved architectural rules.

### T0 — Resolve specification and freeze implementable contracts

- **Goal:** turn contradictions and missing selections into approved requirements before production edits.
- **Files/components:** authoritative `azure.md`, this plan, examples/schema, candidate provider/collection release documentation.
- **Required changes:** record D1–D13 outcomes, with the D12 root-isolation exception approved before schema implementation; choose released AzureRM version; capture exact resource arguments from that tag; confirm target image/SKU/region capabilities read-only; establish baseline existing AWS/GCP plan results and outstanding failures. Do not alter real configs/state during planning.
- **Dependencies:** owners for the unresolved product/security decisions; authority is resolved.
- **Risks:** accepting reference suggestions as facts; treating unverified current deployment as passing baseline.
- **Verification:** approved decision table and requirements cross-check; known limitations separated from regressions. Accept the attributed v4.63 diagnostic in §15.2 as evidence against the tested same-root approaches; do not keep those approaches as unresolved remedies. Approve the entrypoint/state/output exception in D12. If a different release or materially different graph is proposed as a workaround, require new isolated evidence before reconsidering that conclusion. Actual implementation regression plans remain required in T2/T7.
- **Expected result:** a buildable specification and frozen target contract, with no infrastructure created. T0 cannot close until the conflict between `azure.md` §1.4 item 4 and §1.6 has an approved resolution.

### T1 — Configuration and schema first

- **Goal:** express every selected Azure setting explicitly while preserving old configs.
- **Files/components:** `TF/project-config.schema.json`, both examples, relevant schema/runbook documentation.
- **Required changes:** add Azure cloud enum/maps/profile/budget; split image schema; add strict Azure object definitions with `additionalProperties:false`; conditionally require Azure selection fields. Specify RG ownership, tenant/subscription source, image admin user, vault settings/name or deterministic naming rule, egress and trust settings, DB HA representation, monitoring retention/probe locations, budget start date according to decisions. Keep `vms`, `network`, RabbitMQ/Redis, registry, service ports and SSH users semantically neutral. Model disabled HA explicitly rather than an invalid Azure HA string; require standby-zone data when approved mode needs it. Require cloud PostgreSQL port 5432 for Azure. Preserve existing AWS/GCP schemas and validation semantics.
- **Concrete configuration constraints:**
  - Retain shared-schema-required AWS/GCP region, size, disk and image branches in the Azure examples; explicitly disable old-cloud budgets and probes. The proposed Azure root has no GCP module and therefore no runtime dependency on `budgets.gcp.enabled`. That unconditional read remains a legacy-root finding, not a reason to instantiate GCP in the Azure root. Reject enabled features assigned to another root rather than silently ignoring them; D3/D6 must approve how independently hosted probes/budgets are operated.
  - Add `azure` to `monitoring.synthetics.clouds`; derive effective probe selection from explicit list or Azure VM presence when null. If an Azure standard probe is actually enabled, allow only `period_minutes` 5, 10, 15. `runtime_version` remains AWS-only.
  - If an Azure Log Analytics workspace is required and the shared retention field is used, the exact allowable intersection is **30, 60, 90, 120, 150, 180, 365, 400, 545**. Require an explicit compatible value and recommend 30 in Azure deployment examples, subject to D6; do not change the AWS/GCP seven-day default or round it implicitly. Add an enabled-workspace precondition with this list, so direct Terraform runs fail clearly even without schema validation. Do not reject irrelevant retention settings when no workspace is created.
  - Correct example reserved addresses only: recommended management/workload CIDRs `10.0.0.0/24` / `10.0.1.0/24`, bastion `10.0.0.10`, database `10.0.1.10`, History `10.0.1.11`, Fetcher `10.0.1.12`. Keep VM key **`bastion`**, required by root `bastion_public_ip`. UI is `10.0.1.13` for existing GCP workload placement or `10.0.0.13` for existing AWS management placement. Recommend Azure-only subnet selection by containment of `internal_ip`, allowing Azure to accept either layout unchanged. This does **not** make one UI address work across unchanged AWS and GCP implementations; D2 still governs that portability promise. Neither address changes in real deployments nor changes to AWS/GCP placement are approved.
  - Keep required `network_tags` even for Azure. Set `clouds.azure.resource_group_name` explicitly for create and reuse modes: inventory scopes discovery from JSON, not output RG metadata.
  - Proposed cloud-only PostgreSQL subnet `10.0.3.0/28`, contained by `vnet_cidr`, nonoverlapping with management/workload/other allocated ranges. Validate IPv4 prefix **<=28** (at least 16 total addresses), exclusive delegation and same VNet/server region. A `/29` is too small. Do not express IP containment using a string `minLength` check.
  - Configure Key Vault `soft_delete_retention_days` explicitly within 7–90 and make purge-protection policy explicit; development is not implicit permission to disable protection or auto-purge.
- **Dependencies:** T0; especially D2, D4, D6–D12.
- **Risks:** unconditional Azure requirements break existing JSON; image-type union leaks into size/disk; silently clamping retention/storage or remapping IPs; schema doesn't run during Terraform plan.
- **Verification:** static schema validation of examples and existing user-supplied configs using approved schema tooling; manually inspect rejection for missing selected fields, unexpected keys, wrong mode/VM combination. Confirm identical VM entries before/after except explicitly approved portability corrections. No new automated test suite.
- **Expected result:** an explicit selected-cloud contract, with examples labeled illustrative where subscription/image capacity cannot be proven.

### T2 — Isolated Azure root, provider and resource-group ownership

- **Goal:** add an Azure entrypoint while preserving Azure-credential-free legacy plans, subject to D12 architecture approval.
- **Files/components:** proposed `TF/azure/{main,locals,variables,providers,versions,outputs}.tf`, its own `.terraform.lock.hcl`, Azure module provider declarations, legacy `TF/variables.tf` (mandatory entrypoint validation) and `TF/outputs.tf` only if output preconditions are needed to enforce that guard, `.github/workflows/pr-validation.yml`; one RG owner (recommended network module if Terraform-created). Shared schema remains `TF/project-config.schema.json`.
- **Required changes:** use `TF/azure` as a separate root with module sources such as `../modules/azure/network` and `../modules/cloudflare/dns`. Do not call the legacy root as a module, import its state, or declare AWS/GCP providers/resources to obtain empty outputs. Require an explicit `project_config_path` in the new root (`string`, non-nullable, no default); do not copy the legacy workstation path `/Users/pavlo/Desktop/project-config.new.json` or introduce another machine-specific fallback. Preserve file-existence validation and monitoring-default semantics, and validate effective Azure-only VM placement and feature ownership. Do not carry the GCP-only `secret_version_managers` variable into the Azure root; any Azure writer-principal input belongs to D4’s separately approved ownership contract. Keep neutral normalization local to the new root with a documented parity check; resolve shared files such as `monitoring-metrics.json` relative to their owning module (the existing monitoring modules use `path.module`), not an assumed legacy working directory; do not refactor the legacy graph into a shared module. Require a narrow, blocking legacy-entrypoint guard rejecting `default_cloud = "azure"` and any effectively Azure-selected VM before unsafe output map indexing. The diagnostic must direct the operator to `infrastructure/terraform/azure` with an explicit config path and separate state. Prefer input validation on the existing `project_config_path`, parsing the input file without depending on module outputs; handle missing files/malformed JSON without secondary expression errors. File ordering is not evaluation ordering: prove that the guard blocks dependent evaluation on the pinned Terraform version. If needed, add the same blocking output precondition to every affected VM-derived output so no `Invalid index` obscures the entrypoint error. Do not use a warning-only `check` block or silently convert a wrong-root deployment to empty/null success. This mandatory guard must introduce no Azure provider reference, state resource or resource-address change and leave valid AWS/GCP output values intact. Choose a bounded released AzureRM constraint and authenticate through environment/CLI/OIDC with explicit selected subscription, never placeholder credentials/IDs. Configure registration behavior explicitly. Gate optional Azure features within this root and define one RG lifecycle owner. Prefer no AzAPI unless exact-version capability evidence requires it.
- **Complete root provider requirements:** declare `hashicorp/azurerm` with the selected bounded constraint and `cloudflare/cloudflare` with **the same `~> 5.12` constraint as the legacy root** in `TF/azure/versions.tf`; the shared DNS child declares its source but supplies no version constraint, and the sibling legacy root contributes none to Azure initialization. Add an explicit `provider "cloudflare" {}` in `TF/azure/providers.tf`, following the existing environment-token convention and inheriting that configuration into the DNS child. If D5 chooses Terraform-generated admin passwords, also declare `hashicorp/random` with the legacy `~> 3.7` constraint; do not copy unused AWS, Google or archive requirements. Keep shared provider constraints identical across roots. Identical ranges do not guarantee identical selected versions in independent lockfiles: initialize the new root’s shared providers at the existing locked versions and compare both locks; any later divergence requires explicit review, not a blanket legacy upgrade. An omitted provider block can yield Terraform’s implicit empty default configuration, so the explicit Cloudflare block is a clarity/consistency requirement, not a claim that omission invariably leaves no configuration. [Provider configuration](https://developer.hashicorp.com/terraform/language/block/provider), [module provider requirements](https://developer.hashicorp.com/terraform/language/modules/develop/providers).
- **State and lock contract:** use a separate local state directory or explicitly distinct remote backend key/workspace with documented ownership. Never point both roots at the existing state. Preserve the legacy lockfile; generate registry-backed Azure-root checksums for developer platforms and Linux AMD64. No state moves, imports or automatic cloud migration are part of this change.
- **Dependencies:** T1, D1, and explicit D12 approval of the departure from same-root wiring; D3/D6 for cross-root feature policy.
- **Risks:** accidental shared backend key, wrong-root execution, copied defaults drifting, CI validating only the legacy root, and an undocumented operational entrypoint change. Isolation does not make Azure deployment plans credential-free.
- **Verification:** initialize/validate each root independently without cloud credentials; recursive formatting covers both. Extend CI to an explicit two-root list/matrix for init/validate (and the existing test command; do not add a test suite). Check `terraform providers` and configuration dependencies: no Azure provider in the legacy graph and no AWS/GCP providers in the Azure graph. Compare legacy plans against baseline with Azure credentials absent and an isolated empty Azure CLI cache, leaving the operator session unchanged. Verify separate backend identifiers, selected-subscription errors, unchanged old addresses and lockfile, and package installation on both supported platforms. Plan a valid Azure config against the initialized legacy root and require the actionable entrypoint error with no VM-output `Invalid index`; also exercise an Azure VM override under an old-cloud default. This failure mode is source-inferred, not an executed plan result. Confirm a correct Azure-root invocation proceeds, omission of `project_config_path` with noninteractive input fails clearly, no GCP writer variable exists in the Azure root, shared provider constraints and locked versions match, and DNS enabled/disabled plans preserve the intended Cloudflare credential behavior.
- **Expected result:** independently operable roots, unchanged legacy resource/state behavior, and one Azure RG owner. The entrypoint/state contract is approved and documented before later phases depend on it.

### T3 — Network and compute

- **Goal:** private application topology, stable addresses, scoped access and reachable SSH.
- **Files/components:** Azure network `locals/variables/outputs`, VNet/subnets, NSGs/ASGs, routing/NAT, PostgreSQL network topic; Azure VM `main/locals/outputs`, public SSH cloud-init template.
- **Required changes:** preserve neutral subnet CIDRs and validated static IPs; subject to D2, select each Azure NIC subnet by finding exactly one configured management/workload CIDR containing its `internal_ip`. Reject zero or multiple matches, overlapping subnets, reserved addresses and duplicate IPs; never remap the IP or fall back to a role-based subnet. Keep role-based security and public-IP rules independent of subnet selection. This Azure-only logic accepts either existing provider’s valid UI layout without changing AWS/GCP. Use role NSGs attached to NICs, with ASGs or exact configured source IPs to represent role relationships. Explicit allow rules precede a deny for unwanted VNet lateral traffic; account for Azure platform requirements. Network owns NAT/public egress IP; VM module owns conditional ingress public IP/NIC/VM resources, avoiding a network↔VM cycle. Use Standard static public IPs and explicit NAT association for private egress on every subnet containing private VMs, including management if the accepted layout places a private VM there. Build dedicated PostgreSQL subnet/DNS/link only in Azure cloud mode. The subnet must be at least `/28`, contain no workload NICs or unrelated services, carry `Microsoft.DBforPostgreSQL/flexibleServers` delegation, and belong to a VNet in the server region; use the proposed nonoverlapping `10.0.3.0/28` range after validation. Provision per-VM user-assigned identity, attach it, export principal/client/resource IDs. Map all SSH users through cloud-init; select an explicit Azure admin username drawn from that map; validate key support against the chosen image/provider. Do not put private keys or secrets in custom data. Implement approved first-boot SSH strategy.
- **Dependencies:** T2; D2/D10; explicit region/zone/size/image/disk decisions; database network design for T5.
- **Risks:** subnet-reserved IPs, image disk floor, NSG implicit VNet allow, missing egress, provider NSG conflicts, SKU-zone unavailability, VM replacement on custom-data/SSH changes, labels overriding discovery identity.
- **Verification:** inspect plan NIC addresses/subnets, public IP only for permitted roles, identity cardinality, allow/deny ordering; inspect boot user/sshd configuration without applying. Confirm no unrelated inbound PostgreSQL/Redis/RabbitMQ management/diagnostic ports. Check NSG egress allows Azure platform/metadata dependencies as required.
- **Expected result:** deployable VM/network plan with protected discovery tags and dependency-ready private PostgreSQL network output.

### T4 — Secret catalog and least-privilege grants

- **Goal:** support existing logical secret mappings without Terraform ingesting workload values.
- **Files/components:** Azure secrets module and output wiring; exact workload identity inputs from T3.
- **Required changes:** implement approved D4 topology. Recommended design for evaluation: Terraform manages one vault, deterministic logical-ID→versionless-URI catalog and per-secret read role assignments; controller creates first real secret version. Prove Azure accepts resource-scoped grants before a version exists; if not, return to D4 and do not widen every VM to vault-wide read. Use one vault as the intended topology. The cloud example has five distinct readership sets for six secrets; per-readership vaults add disproportionate naming/network/lifecycle work and are not the planned fallback. If pre-creation secret-scoped grants are unavailable, D4 must approve controller-managed grants after first version creation or another least-privilege design; do not automatically widen access. Require secret IDs to match `^[A-Za-z0-9-]{1,127}$` for Azure, with a selected-Azure precondition identifying each invalid non-secret ID; detect case-insensitive collisions too. Existing schema allows underscores, so old AWS/GCP mappings remain valid. Reject rather than silently substitute `_` with `-`. Catalog URI must match versionless secret URI syntax, using the vault’s exported URI plus `secrets/<name>`; RBAC scope is vault ARM ID plus `/secrets/<name>`, not the HTTPS URI. Separate admin secret from workload grants. Define writer principal ownership and data-plane reachability for controller/VMs. Catalog describes *intended secret addresses*, not fictitious existing containers. Do not use `value` or `value_wo` placeholders: an absent version fails a premature read, while a placeholder returns a successfully read **wrong credential**. Write-only storage does not fix that semantic failure.
- **Dependencies:** T3; D4/D5/D9; network endpoint policy.
- **Risks:** ARM secret scope confused with HTTPS URI; role propagation; controller cannot reach restricted vault; accidental secret overwrite/read permission; soft-delete name reuse; managed secret deletion ownership unclear when Terraform owns no versions.
- **Verification:** inspect exact grant matrix against `workload_secret_access`; ensure no runtime grants on admin secret, no wildcard vault read, no placeholder or workload secret values in plan/output. Document first-version and destroy/restore procedures. Scope existence remains a live/provider capability gate if not provable read-only.
- **Expected result:** non-secret Azure catalog and bounded identity grants with explicit payload ownership.

### T5 — Managed PostgreSQL and trust metadata

- **Goal:** Azure cloud mode runs the unchanged migration/runtime database contract.
- **Files/components:** Azure database module `locals/main/secrets/outputs`, TLS configuration and DB resource; T3 delegated network.
- **Required changes:** gate on `default_cloud == "azure" && managed_database == true`. Create Flexible Server, application database `oil_tracker`, password-auth admin identity, and approved admin secret lifecycle. Use native FQDN, port 5432, private VNet integration, DNS zone ending `.postgres.database.azure.com`, explicit DNS-link dependency, public access disabled, and secure transport enforcement. Take SKU/version/storage/backup/HA/zone from selected JSON, accounting for HA capacity constraints. Do not assume Azure admin is PostgreSQL superuser: review existing role/grant SQL against managed admin permissions without changing SQL. Expose only admin reference and trust metadata; implement D8 bundle strategy.
- **Dependencies:** T3–T4, D5/D8/D11.
- **Risks:** managed admin permissions insufficient; differing PG major version; credential rotation updates server and vault out of order; accidental database retention change; FQDN/SAN mismatch; failover zone drift. If application/SQL changes appear necessary, stop and raise scope conflict.
- **Verification:** both mode plans, no database/subnet/DNS/admin-secret artifacts in application mode; correct PostgreSQL version/profile fields; null disabled outputs; inspect output references only. Live DNS/TLS and role-grant verification deferred to separately authorized deployment.
- **Expected result:** stable private connection contract and no admin privileges granted to workload identities.

### T6 — Monitoring, logs, alerts, dashboard and availability

- **Goal:** preserve observable signals and toggles, with explicit Azure differences.
- **Files/components:** Azure monitoring module with locals/agent/logs/application/alarms/dashboard/notifications/uptime/outputs topics; VM extension wiring only under chosen ownership.
- **Required changes:** Log Analytics workspace and custom tables, DCR(s)/associations, identity-aware agent metadata, action group, native VM/DB metric alerts, log-query alerts for collector/HTTP/guest signals where appropriate, dashboard/workbook selection under D6. Build from existing `monitoring-metrics.json`; retain role-based signal selection, units, thresholds and missing-data/collection-failure semantics. Bastion remains excluded. Support Traefik access logs separately from service logs and application metric JSONL. Terraform owns DCRs and associations; recommend Terraform owns AMA VM extension too, with Ansible validating it and preparing files—requires D7 approval. Use supported standard availability test plus Application Insights only if D6 accepts its semantic limits. Do not silently ignore browser flag, unsupported intervals, or unsupported retention. If browser journeys are requested, require an enabled AWS browser probe or a separately approved Azure runner; an Azure standard probe does not satisfy them. Do not reject a valid AWS browser probe merely because Azure VMs or Azure standard probes coexist. For Azure-only probes reject browser requests explicitly. Decide whether the EC2-only detailed-monitoring flag is documented as AWS-only (as on existing GCP) or rejected when Azure is the sole workload cloud; do not invent equivalent paid Azure behavior. Budget recipients remain separate.
- **Dependencies:** T3/T5 plus T4 identity policy; D6 and **D7 approved before T6 starts**. Terraform-owned AMA moves installation from the task’s Phase 2 into Phase 1; it is a change of responsibility requiring agreement, not merely an A4 detail.
- **Risks:** treating logs as metric namespaces; missing-data queries with no first sample; flat JSON incompatibility with nested records; double ingestion, stale container links after recreation; no-logs mode still needs collector transport; extension/DCR drift from dual ownership; workspace costs/quotas and region mismatch.
- **Verification:** manually inspect all flag combinations as a validation matrix, including monitoring off, only access logs, only application metrics, service logs, guest metrics, DB metrics in both modes, alarms without recipients, and probes without Azure VMs. Check `agent_configurations` includes any VM requiring collector log shipping even with `agent_metrics_enabled=false`. Confirm absent metrics do not become healthy zeroes. Validate KQL/table schema and supported resource arguments against pinned provider.
- **Expected result:** complete agreed Azure monitoring resource plan and consumable per-VM payloads; actual telemetry/delivery remains unproven until deployment.

### T7 — Budget, root outputs and DNS integration

- **Goal:** complete the deployment graph and freeze Phase 1 contract.
- **Files/components:** Azure budget module; new `TF/azure/{main,outputs}.tf`; shared Cloudflare DNS input/map; contract documentation.
- **Required changes:** use approved subscription or RG budget scope, explicit start date, billing currency assertion, and configured recipients. Preserve `actual_thresholds` as **currency amounts**; Azure notification percentage is `100 * threshold / monthly_amount`; the existing GCP budget already follows this normalization pattern, using a fraction rather than Azure’s percentage units. Gate budget independently of operational monitoring and define standalone Azure budget activation. Implement the existing VM/secret/budget aggregate contract in the new Azure root and add Azure DB/monitoring/deployment metadata there; do not extend the legacy graph with Azure module references. Cloudflare uses Azure UI public IP and direct-to-origin TLS. Wire both `azure_vms` input and the `public_ips.azure` entry; guard missing/null address handling so an intended validation is not preempted by `coalesce` of empty strings. Record that the existing typed `proxied` field is not actually validated despite the source comment; adding that enforcement is not needed for Azure and is not silently included.
- **Dependencies:** T4–T6; D9 and feature activation rules.
- **Risks:** bill-currency mismatch, threshold limits, end-date expiry, `timestamp()` forcing perpetual budget replacement, extra AWS/GCP budgets/probes in “Azure-only” acceptance, Cloudflare modifying an existing production record.
- **Verification:** review saved plan JSON privately; compare AWS/GCP resource changes to baseline using same inputs/state/provider locks. Distinguish additive output shape differences from infrastructure diffs. Inspect complete output shapes and zero credential values. Azure-only acceptance configuration explicitly disables AWS/GCP budgets and probes. Do not apply DNS changes.
- **Expected result:** Phase 1 complete, with reviewable plan evidence and frozen contract. **Stop for required Terraform review before any Ansible implementation.**

## 6. Proposed output-contract changes to freeze at Phase 1 review

Legacy-root outputs remain intact. The separate Azure root must emit the same names, types, null/empty semantics and Terraform JSON `{value: ...}` envelope required by existing Ansible consumers, plus the Azure fields below. Inactive AWS/GCP connection and monitoring fields must be contract-compatible null/empty literals, not module references. Freeze the complete consumer-visible output inventory at Phase 1 review, including actual exported behavior for null outputs; consumers must preserve existing absent/null handling. Besides the fields below, account explicitly for `dns`, `workload_roles`, `workload_secret_access`, `workload_network_tags` and `workload_service_account_emails`; the latter two are empty maps on Azure. Proposed Azure-root contract:

| Output/component | Shape and semantics |
| --- | --- |
| Azure VM module `vms` | Map keyed by original VM key: `name`, `instance_id` (document Azure ARM ID semantics), `internal_ip`, nullable `public_ip`, `identity_resource_id`, `identity_principal_id`, `identity_client_id`. Optional native fields stay Azure-specific. |
| Azure network outputs | RG name/ID/location, VNet ID, management/workload subnet IDs, role NSG/ASG IDs, nullable PostgreSQL object containing delegated subnet/private DNS IDs. Carry DNS-link readiness through dependencies, not merely string IDs. |
| Azure secrets module | `secret_ids` = logical IDs; `secret_resource_names` = logical ID → versionless HTTPS URI. Additional private module map for ARM grant scopes. Disabled: empty collections. Use full URI catalog entries so resolver code does not reconstruct names or confuse data-plane URIs with ARM scopes; the proposed deployment uses one vault. |
| Root `azure_deployment` (proposed new output) | Non-secret subscription/RG/location and `identities` keyed by VM key with managed identity client/resource IDs. Gives resolver/agent explicit identity selection and deployment provenance. Use only if not duplicated by a chosen inventory metadata contract; finalize one source of truth. |
| Azure database module `monitoring` | `{id = <Flexible Server ARM resource ID>}` in Azure cloud mode, otherwise null; consumed by Azure monitoring independently of root connection metadata. |
| Root `azure_database_connection` | Object or null: `host`, `port`, `database`, `admin_username`, `admin_secret_id` (versionless Azure secret URI, JSON payload containing password), `sslmode="verify-full"`, approved CA fields. Match GCP field name for the reference but add explicit Azure dispatch, not an implicit GCP fallback. |
| Root `azure_monitoring` | Stable object, including nullable native IDs (`workspace_id`, `action_group_id`, dashboard/availability IDs), alert IDs, and always-present `agent_configurations={}` / `collector_configurations={}` when disabled. No workspace shared keys. |
| Azure agent map entry | Object: VM ARM ID, identity client/resource ID, DCR/association IDs, extension name/expected provisioning metadata, required local paths, ownership mode. Unlike AWS JSON/GCP YAML, this is not a file to pass to a standalone installer. |
| Azure collector map entry | `cloud="azure"`, `vm_key`, native resource identifier, and approved local JSONL destination/schema version. Recommended AMA shipping needs no cloud token in collector. `role`, History port and RabbitMQ details remain merged by existing role. |
| Azure-root equivalents of existing aggregates | Produce secret-resource and budget maps and VM-derived locals from Azure modules. Preserve `bastion_public_ip` and `workload_*` public output names, types and null semantics; leave legacy aggregate expressions unchanged. |

**Trust contract alternatives (D8):** preserve `ca_bundle_url` only if an actual maintained complete bundle endpoint is approved. Otherwise add an explicit discriminated trust field for Azure (system trust-store source or a `ca_certificates` list of root URLs/checksums) and adapt `database_connection` to stage one PEM file; AWS/GCP continue their existing URL path. The reference demands a singular URL; changing it needs an explicit contract decision, not a fabricated URL.

The existing Ansible output-file parameter remains root-neutral: export `terraform -chdir=infrastructure/terraform/azure output -json` to the chosen handoff file. No Ansible consumer may assume the legacy Terraform working directory. Output file must be freshly exported from the **applied** deployment before runtime use. A plan predicts unknown IDs and cannot be an Ansible inventory/credentials source. Reject absent/mismatched Azure metadata rather than selecting another cloud or a different VM's identity.

## 7. Ansible implementation phases — after Phase 1 review

### A1 — Dependencies and Azure inventory

- **Goal:** discover exactly the configured Azure hosts with trusted role/cloud/key identity and usable SSH.
- **Files/components:** collection/controller requirements, galaxy/runtime metadata; new inventory plugin and source; shared helper; inventory/collection docs.
- **Required changes:** select released Azure collection and compatible Python SDK dependencies from that release’s requirements. Update both controller `requirements.yml` and the installable collection’s `galaxy.yml` dependency map plus `azure` tag; collection consumers need the latter independently of the controller requirements file. Set `requires_ansible` to the maximum floor across the three chosen cloud collection releases and repository needs. Wrap `azure.azcollection.azure_rm` using the concrete settings below; preserve its default stopped/unprovisioned exclusions. Use raw VM `name` or protected tag for key derivation; verify against config. Set role/cloud/internal/public address, required managed-identity metadata if chosen, role groups and workloads, then shared validation/connection helpers. Match delegate filename requirements. Preserve cache isolation and failure behavior. Require explicit operator SSH key for documented Azure workflow; all configured users must exist after boot.
- **Delegate settings:** `subscription_id` and `include_vm_resource_groups:[resource_group_name]`; leave VMSS/Arc/HCI discovery empty unless explicitly in scope. Use one `include_host_filters` expression combining location **and** application **and** environment checks, because entries in this list are ORed. Use `hostvar_expressions` for `oilscope_*` and connection facts, `conditional_groups` for workloads, and `keyed_groups` for role groups. Preserve `default_host_filters` and `fail_on_template_errors:true`. Generated delegate filename must end in `azure_rm.yml`/`azure_rm.yaml`. Current docs also expose `compose`/`groups`, contrary to the review; avoid ambiguity by using the Azure-specific interface supported by the selected release. `plain_host_names:true` is appropriate only with exact RG scope and unique VM names; regardless of presentation, derive VM key from raw `name`/protected tag, never inventory alias. Keep shared helper/preflight safety checks. `azure_kql` is a possible alternative but unnecessary here.
- **Dependency exit gate:** build/install/import and run inventory/lint dependencies in the existing Ansible CI Python 3.14 environment. If a selected dependency demonstrably does not support it, propose a scoped move of **both** Ansible job Python settings (setup and lint action) to supported 3.12, already used by the separate Python job; verify all three cloud collections there. Do not downgrade CI preemptively or claim all jobs run Python 3.12.
- **Dependencies:** reviewed T7; D7 and dependency release verification.
- **Risks:** decorated inventory hostname used as key; an implementer disabling safe `fail_on_template_errors`; OR-combined include filters accidentally broadening discovery; cache cross-contamination; missing bastion; duplicate instance keys masked by plain host naming.
- **Verification:** syntax/lint and collection build/install; read-only `ansible-inventory --list/--graph` only with authorized existing Azure resources. Manually validate missing/stale/tag-mismatch/renamed-host behavior and `--limit` safety without deploying workloads. No new automated tests.
- **Expected result:** equivalent role groups and identity facts for Azure, preserving AWS/GCP discovery.

### A2 — Runtime secret reads and controller uploads

- **Goal:** connect each workload and the operator to the approved Key Vault catalog with distinct identities.
- **Files/components:** resolver/uploader main dispatch and new Azure task files; defaults/meta/docs; upload playbook only where needed for outputs path.
- **Required changes:** **first**, fix the existing `secret_versions/tasks/main.yml` unknown-cloud success-without-upload gap with an early fail before catalog/value work, accepting only implemented backends; mirror resolver guard wording. If the independent AWS/GCP-only maintenance fix described in §9 has already landed, verify and retain it; otherwise implement it here after Terraform review. Then add Azure to the guard and implement Azure dispatch together; never accept Azure before a working backend exists. Runtime uses Azure IMDS managed-identity token with explicit intended user-assigned identity, no proxy to metadata, Key Vault token audience, HTTPS verified secret GET, bounded propagation retries and `no_log`. Resolve versionless URI from reviewed catalog using `oilscope_vm_key` and logical mappings. Controller upload uses operator credentials and stable catalog; preflight all source values before any write, preserve exact strings/newlines, and never use secret literal command arguments. Create real first versions if D4 approves; document its difference from AWS's describe-existing-container guard. Add unknown-cloud failure before dispatch so Azure cannot silently no-op.
- **Dependencies:** A1, reviewed T4 contract; controller data-plane reachability and writer grants.
- **Risks:** managed-identity selection ambiguity, stale URIs, PUT creates unexpected names, partial upload on API failure, secret values in registers/temp files/process args, creating versions on every unnecessary run.
- **Verification:** syntax/lint plus, only in authorized environment, exact secret round-trip with nonproduction payload, denied unmapped-secret access and denied admin-secret access from each VM; no value logging. Check temporary-file cleanup on failure and all-source preflight. Preserve AWS/GCP task behavior.
- **Expected result:** `resolve_secrets_result` remains environment-name → value; infrastructure and outputs carry references only.

### A3 — Managed migrations and verified TLS

- **Goal:** run existing images/SQL against Azure through History with transient admin access.
- **Files/components:** `database_migrate/tasks/{main,read_secret,runtime}.yml`; `database_connection` tasks/vars; associated docs.
- **Required changes:** add an early supported-cloud failure in `read_secret.yml`, followed by explicit three-cloud secret read dispatch; controller resolves Azure admin URI and runtime logical IDs through the same catalog; Azure `read_secret.yml` returns the **raw secret string**, matching GCP: decode the Key Vault response envelope once to obtain `value`, then decode that string as JSON only for the admin object in `main.yml`; `runtime.yml` consumes raw passwords unchanged. Preserve AWS’s existing CLI-envelope decoding. Without this branch Azure currently falls into an undefined GCP register inside `no_log`, producing a misleading diagnostic. Scrub Azure registers/tokens in `always`. Implement approved multi-root trust provisioning into the existing PEM mount and checksum mechanism; retain `verify-full`. Use native DB DNS hostname, never IP or arbitrary alias. Keep migration prerequisites and order; clarify one supported History migrator.
- **Dependencies:** A2, T5 output and D8 decision.
- **Risks:** accidental controller-to-private-DB connection, granting admin secret to VM, permission mismatch in managed PostgreSQL, incorrect CA format, parallel migration on multiple History hosts, rotation race.
- **Verification:** static rendering/contract checks; authorized runtime checks include TLS success and wrong-host/wrong-CA failure, admin bootstrap, Fetcher/History restricted role access, migration rerun, and no admin-secret runtime access. Application mode still uses database VM, shared configured password and existing SSL behavior.
- **Expected result:** identical database environment for unchanged services in both modes.

### A4 — AMA integration and application telemetry

- **Goal:** make Terraform-defined monitoring receive real, correctly attributed data.
- **Files/components:** monitoring-agent Azure tasks and disable dispatch; application-monitoring tasks/collector publication; metadata/docs and rotation files as needed.
- **Required changes:** first remove the shared AWS-else-GCP disable-path assumptions, using explicit cloud lifecycle dispatch. Then implement approved agent ownership. Recommended Terraform-owned extension: Ansible verifies expected agent/association/service readiness and prepares local log sources; it does not create a competing DCR. If Ansible owns extension, execute ARM operations from controller with operator identity and define removal on disable. Add flat Azure JSONL publication to `collect.py` without changing probes or services; emit timestamp, VM key, resource identity and finite metrics; rotate logs. For the chosen explicit per-service file strategy, reuse the existing service-log link block by widening its cloud condition to AWS/Azure instead of copying it; first confirm AMA follows these links with its configured paths/permissions. If it does not, route the actual source paths explicitly and document that small Azure exception. Configure Docker/Traefik parsing and refresh links/paths after container recreation. Explicitly handle Azure removal/disable instead of falling into GCP service paths. Keep collector shipping active if application metrics alone enabled.
- **Dependencies:** A1/A2; reviewed T6 contract and D6/D7.
- **Risks:** initial AMA startup before files exist, inaccessible root-only log directory, unsupported symlink/wildcard collection, nested Docker JSON needing transforms, duplicate streams, stale DCRs, local buffers growing while offline.
- **Verification:** syntax/lint; in authorized environment verify agent and timer, a fresh sample of every enabled signal/log, data attribution, alert firing/recovery/absence and notifications, enable/disable/re-enable and container recreation. Standard availability result does not prove browser behavior.
- **Expected result:** observable parity under agreed semantics with bounded local collection and no cloud secrets in collector config.

### A5 — Integration, regression and handoff

- **Goal:** demonstrate the supported end-to-end path without widening task scope.
- **Files/components:** existing playbooks/wrapper/preflight, docs; no application files.
- **Required changes:** minimal integration adjustments only; preserve deploy order and early failure. Update examples/commands to select Azure inventory and fresh outputs. Deliver completed acceptance evidence and remaining environment-dependent gates separately.
- **Dependencies:** A1–A4; separate authorization for any live changes.
- **Risks:** claiming syntax/plan as successful deployment; preexisting AWS/GCP failures mistaken for Azure regressions; cost/destructive mode-switch operations performed without authorization.
- **Verification:** approved end-to-end deployment for each Azure database mode, zero failed/unreachable hosts, existing smoke observations, managed migration idempotency, routine redeploy preserves volumes. Re-run at least one AWS/GCP deployment only when authorized; statically/plan-check both. No newly written automated suite.
- **Expected result:** documented support based on actual evidence, or an explicit pending-live-validation status.

## 8. Documentation phases

### DOC1 — Terraform configuration and contract documentation

- **Goal:** make Phase 1 independently reviewable.
- **Files/components:** root README; `docs/{database-modes,monitoring,secrets,dns}.md`; Azure module READMEs; schema/example explanations.
- **Required changes:** Azure alongside existing providers; strict settings, naming, prerequisites/permissions, RG ownership, secret first-version/admin lifecycle, TLS roots, actual budget scope/currency/dates, feature toggles and limitations, estimated cost components without promises of free hosting. Explain native FQDN, operator versus runtime identities, subnet-reserved addresses, valid image disk floor, required-but-ignored Azure `network_tags`, and first-boot SSH. Document the two Terraform entrypoints, explicit config-path handling, separate backend keys/locks, root-specific feature ownership and Azure output export command. Update every Azure init/plan/apply/output example to use the new root after D12 approval; no implicit state migration. Add Azure vault/secret soft-delete recovery, protected name reuse and explicit purge policy to fresh-deployment and cutover guidance. Distinguish Flexible Server’s own dropped-server restore/name behavior from Key Vault’s 7–90-day retention; do not claim identical retention or guaranteed immediate reuse. Correct directly affected inaccuracies without rewriting historical handoff facts.
- **Dependencies:** T1–T7 decisions and contract.
- **Risks:** showing invalid placeholders as validated deployable resources; publishing environment identifiers/values unnecessarily; implying live apply authorization.
- **Verification:** compare every command/field/output name to implementation and actual selected-version docs; cross-check two-mode tables.
- **Expected result:** Phase 1 configuration/contract documentation approved with Terraform.

### DOC2 — Ansible operations and acceptance evidence

- **Goal:** make deployment repeatable by another operator.
- **Files/components:** inventory README; collection README/CHANGELOG/plugins README; resolver/uploader/agent/migration/connection/application-monitoring READMEs; root docs updates.
- **Required changes:** add Azure peer subsections under inventory README’s **How it fits together**, **Setup**, **Usage**, and **When it looks broken**. Make `OILSCOPE_SSH_KEY` an explicit required Azure setup step (shared helper otherwise selects a GCP key). Cover Azure auth/SDK installation, inventory filters/key/cache, bootstrap, secret upload inputs, migration/deploy order, trust refresh, disable cleanup, verification, rollback limitations and fresh-output requirement. Separate implemented, planned and live-verified status. Clarify root-specific probes and budgets: the legacy root supports independent AWS/GCP resources, whereas the Azure root must not silently create them. Any approved external AWS browser probes require a separately applied, explicitly scoped deployment and its own state/config; cross-root orchestration is not implicitly included.
- **Dependencies:** A1–A5.
- **Risks:** documentation repeating unverified “all clouds supported” or existing stale mock-test claims; credentials in examples.
- **Verification:** follow runbook against authorized validation environment; static link/name review; no live completion claim without results.
- **Expected result:** accurate three-cloud operating guidance and explicit remaining limitations.

## 9. Dependencies and ordering

`Blocking decisions (D12 architecture exception before T1; D7 before T6) → T0 → T1 schema → T2 provider/RG → T3 network/VM → T4 secret catalog → T5 database → T6 monitoring → T7 outputs/DNS/budget → DOC1 + Terraform review → A1 → A2 → A3/A4 → A5 + DOC2`.

Terraform resource graph should remain acyclic: config/RG → network and identities/VMs → secret grants, database and monitoring → root outputs/DNS. Database admin secret ownership must not make workload secrets depend on database while database depends on the whole secrets output. Pass the narrow vault/RG/network data actually required. VM identity creation must not depend on monitoring outputs if monitoring already consumes VM IDs; place monitor grants/extensions in monitoring or a narrow downstream owner.

Independent work inside Terraform is possible once schema and decisions are fixed. It does not authorize interleaving Ansible implementation before review. The pre-existing uploader guard (H2) can be a separately commissioned maintenance change before the Azure Phase 1 review: restrict accepted clouds to currently implemented AWS/GCP, reject unknown values, and verify failure precedes success reporting. It has no Azure dependency and must not enable Azure dispatch early. If not separately scoped, it remains part of A2 after review. This option does not waive the authoritative Azure Phase 1 → review → Phase 2 ordering. No production change is authorized by this planning revision. No sub-agents were used for this investigation.

## 10. Risks, edge cases and backward compatibility

- **Baseline must separate plan-time and apply-time validity:** example reserved IPs and AWS UI/subnet mismatch can pass Terraform planning and fail at cloud creation. Real credential/input requirements can independently prevent a plan. The local recorded deployment uses nonreserved addresses; obtain its reproducible baseline without modifying state. Record unrelated drift/failures and do not silently “fix AWS” during Azure integration.
- **Default versus effective cloud:** schema calls deployment single-cloud, VM overrides permit otherwise, managed DB and DNS use default cloud. A same-cloud VM fleet overriding a different default can still get the wrong managed DB. Keep unsupported topology explicit; D3 must establish whether to reject it.
- **Cloud switching in one state is destructive:** adding Azure support must not migrate an existing AWS state by changing default cloud. Use separately reviewed state/config strategy for independent deployments. No cross-cloud data migration or failover is included.
- **No Azure keys in legacy JSON:** inactive Azure must not require selected-Azure JSON or authentication. New Azure fields are optional for legacy configurations and required for active Azure features. Approve D12 root isolation **before T1**; the supplied v4.63 results rule out the tested GUID/count/module-count remedies.
- **No output renames or AWS/GCP replacements:** legacy outputs and resource addresses remain intact. Azure-root output keys are additive to the shared consumer contract; existing consumers selecting `.value` remain valid. Root selection changes the exported deployment, so reject stale/mismatched handoff files.
- **Discovery identity:** protect application/environment/role/VM-key tags from conflicting custom labels; inventory aliases cannot determine secrets. Cloud API discovery does not replace deployment provenance validation.
- **Resource uniqueness:** logical VM keys are already unique within `vms` and each is assigned one cloud. Mixed cloud does not automatically duplicate keys; the real missing features are cross-cloud routing, DNS, inventory/preflight and database selection. Independent deployments in separate states need independent environment/name/DNS strategy.
- **Azure names/lifecycle:** vault/DB naming restrictions, global uniqueness and soft-delete recovery/purge settings need a deterministic strategy. Avoid hidden random renaming or automatic purge to solve collisions.
- **Local disk data:** RabbitMQ/Redis/PostgreSQL container persistence survives routine Compose redeploy but not arbitrary VM/disk replacement; scope does not add HA or backups for these services.
- **SKU, HA, image and disk:** confirm target subscription quota, burstable limits, image architecture versus published application images, supported key types, image generation/security settings and disk floor. A smaller VM size is not equivalent just because its price class matches a tier name.
- **Bastion bootstrap:** examples use port 8787; images initially use 22. Existing GCP bootstrap firewall flag is hardcoded false. Azure must have an approved working first connection, not merely a firewall rule for the final port.
- **Provider and API drift:** documentation includes newer fields; a released pin may not. Record selected-tag schema and any AzAPI necessity explicitly rather than downgrading silently.

## 11. Security considerations

- Keep workload secret values out of configuration, Terraform resources/state and outputs. Admin-secret exception is governed by D5. Treat state and saved plan as sensitive regardless of output markings; JSON plan exports can contain raw sensitive data.
- Distinguish controller ARM discovery/provisioning rights, controller Key Vault writer/read rights, and VM secret-reader rights. Provisioning role-assignment rights are privileged and should not be granted to workload identities. No vault-wide read shortcut or VM admin-secret grant.
- Use explicit managed identity client selection; IMDS requests bypass proxies, token audience matches Key Vault, HTTPS validates certificates. Never echo tokens or put values in command arguments; protect temporary payload files and delete them even on failure; facts/registers use `no_log` and cleanup.
- Private workload/database access and minimum allowed ingress: public SSH only to bastion from configured CIDRs, public 80/443 only where requested for UI; SSH to workloads only from bastion; UI→History API; Fetcher/History→RabbitMQ TLS and PostgreSQL. Redis remains host-local Docker. Suppress Azure's implicit broad VNet access where it would undermine these rules, while permitting required platform flows.
- Choose vault public-with-firewall versus private endpoint deliberately. A private vault requires controller connectivity/DNS, even if VMs can reach it. Trusted-services bypass is not a universal VM/controller bypass.
- Preserve database hostname verification and root lifecycle, no plaintext/unverified fallback. Keep Cloudflare DNS-only for TLS-ALPN-01. Certificates, public SSH keys and identity IDs are not secret credentials but still need correct provenance.
- Do not give monitoring shared workspace keys to VMs. Use managed identity/DCR transport. Exclude secret-bearing container environments; only intended log files/diagnostics are collected. Maintain retention and access controls for logs.
- Budget alerts do not enforce spending limits. NAT, IPs, workspace ingestion, alerts, probes, DB backup retention and resource retention all have costs. Review separately before apply; the task's plan-only authorization does not include subscription registrations or destructive cleanup.

## 12. Validation strategy

### Design-stage evidence (this document)

Read-only source audit, network-only local-state inspection and primary-documentation checks were completed. A manual provider-free `terraform console` expression under Terraform 1.15.8 returned a heterogeneous object successfully (details §15). No Terraform provider init/plan/validate, Ansible deployment, automated test suite or cloud mutation was run for this revision. Numeric Azure provider/collection release pins, real subscription SKU availability, grant-before-first-secret feasibility, and all runtime acceptance remain unverified. The follow-up reviewer supplied v4.63 provider-plan diagnostics, summarized with attribution in §15.2; those were not independently rerun here. They resolve the tested same-root feasibility question, while D12 architecture approval and full implementation regression plans remain outstanding.

### Phase 1 static and plan validation

1. Establish baseline with approved existing configs/state and current provider locks; record failures before edits. Use explicit `project_config_path`. Do not fabricate a temporary copy of the real Desktop configuration contrary to the prior handoff; obtain designated validation configurations.
2. Run schema validation explicitly; JSON parsing and Terraform validate do not enforce JSON Schema. Validate both example modes and legacy AWS/GCP configs. No new automated test framework.
3. Run `terraform init -backend=false -input=false`, `terraform validate`, `terraform fmt -check -recursive` for each root in an appropriate validation checkout (format recursively from `TF`). Confirm CI covers both roots, because init/validate do not recurse into nested roots. Review each root’s lock changes; do not upgrade existing providers implicitly.
4. Obtain read-only plan evidence using actual authorized credentials/configs; watch provider automatic registration. Inspect Azure application and cloud plans, monitor flag combinations, independent budget/probe behavior and missing-selected-key failures. Count resources by provider and mode, not module labels alone.
5. Compare AWS and GCP plans semantically with baseline under identical inputs/state, accounting for drift and unknown IDs. Do not require byte-identical saved-plan binaries/JSON: timestamps, ordering and additive outputs are not infrastructure changes. Compare resource addresses, actions and before/after attributes, and separately enumerate allowed output additions. New Azure integration must create no infrastructure changes in old deployments and must not demand Azure credentials. Do not remove resources or `-target` around provider failures to manufacture acceptance.
6. Inspect Terraform output expressions/plan JSON privately for credential leakage; keep saved plans out of source control. Confirm typed nullable DB output and stable empty maps for disabled monitoring.
7. Review all resource contracts against the pinned AzureRM provider schema, then freeze the output schema and record Phase 1 review before A1.

### Phase 2 static validation

Run collection build/install, Ansible syntax checks, ansible-lint and yamllint on changed scope. Verify Azure collection dependencies in CI's Python/Ansible environment. Inventory listing is read-only but requires a real deployed environment; absence of resources is not proof of complete discovery. Existing CI’s `terraform test` currently has zero `.tftest.hcl`/`.tftest.json` files to execute; it is not a new-suite policy conflict and needs no policy change. Keep the no-new-tests constraint and do not expand this planning task into running existing Python/Ansible suites. D13 concerns live acceptance only.

### Separately authorized live acceptance

- Confirm complete inventory, renamed aliases preserving original keys, bastion proxy, wrong-cloud/tag/missing/duplicate host rejection and zero-host wrapper failure.
- For both modes: deploy order, zero failed/unreachable recap, startup/readiness and observable message/session flow with unchanged images.
- For cloud mode: private DB resolution from History/Fetcher; TLS certificate and hostname validation; negative trust/hostname checks; runtime permissions and migration rerun. UI/bastion should not gain DB access.
- Check VM secret access matrix including denied unmapped/admin reads; controller upload/migration permissions distinct; exact string round-trip and version handling.
- Check requested logs/metrics/alerts/dashboard/availability and notification delivery; no bastion collection; absent-data alarms and disable/re-enable cleanup; billing budget configuration rather than a promised immediate spend email.
- Re-run at least one old-cloud deployment with authorization; keep both old clouds covered by configuration/static/plan comparison. Never report “unaffected” based only on lint.
- Review mode-switch/destroy plan separately. No destructive reset, backup purge, resource apply or failure injection on production is authorized by this planning request.

## 13. Acceptance-criteria mapping against `azure.md`

| Specification criterion | Implementation coverage | Evidence / outstanding gate |
| --- | --- | --- |
| Third cloud, unchanged applications | T1–T7, A1–A5 | Scope diff excludes services/database/images; authorized runtime observations |
| Neutral VM/workload definitions | T1/T3 | Repair example-only reserved IPs; resolve remaining UI-placement contradiction and image disk floor in D2/D11 without changing live configs |
| Terraform before Ansible, schema first | T0–T7 / review boundary | Review record required before A1 |
| Strict Azure config, no selected-value fallback | T1/T2 | Schema validation plus plan failure for missing fields; clarify existing default exceptions |
| Network/VM/secrets/managed DB | T3–T5 | Full provider plan, then separate live validation; D4/D5 unresolved |
| Monitoring and budget parity | T6/T7, A4 | D6–D9 define meaningful parity/currency/retention/probe scope |
| init/validate/fmt success | T2/T7 | Static command results, not executed during planning |
| Azure plan, zero AWS/GCP resources | T1/T7 | Retain AWS/GCP region/size/disk/image branches because the shared schema requires them (`region_entry`/`per_cloud_string`, retaining requirements in the split image definition); explicitly add Azure properties to these closed definitions. Disabled AWS/GCP budget blocks are example hygiene, not an Azure-root Terraform dependency. Reject enabled non-Azure features; compare provider counts |
| Existing AWS plan unchanged / same-root wiring conflict | T0/T2/T7, D12 | Approve explicit exception to `azure.md` §1.4 item 4; separate root preserves §1.6. Same baseline legacy inputs/state/locks and output contract, semantically unchanged actions, no Azure auth requirement. If exception is declined, compatibility remains blocked. |
| Both DB modes | T5/A3 | Correct single inverted clause: cloud forbids DB VM; application creates no managed server and requires DB VM |
| No secret values in outputs | T4/T5/T7 | Inspect all root outputs, including nested monitor/identity data; state policy separate |
| Inventory correctness / proxy SSH | A1 | Full deployed-host graph and safety failures; apply not currently authorized |
| End-to-end deploy order and success | A3/A5 | Authorized recaps/readiness, no false success on missing database/inventory |
| ansible-lint and yamllint | A1–A5 | Static results in chosen dependency environment |
| AWS/GCP unaffected; rerun one | A5 | Both plan comparisons, at least one authorized live rerun; do not assume historic deployment success |
| Documentation complete | DOC1/DOC2 | Commands, contracts, side-by-side provider guidance and actual verification status |
| No automated tests added / no unauthorized apply | All phases | Diff and execution audit; CI Terraform test invocation has no test files; live approval is separate |

This mapping uses `azure.md` as the authoritative specification; listed corrections/deviations remain explicit, not silent edits to that file.

## 14. Unresolved decisions and recommendations

Recommendations below are proposals, not approvals. A blocking decision may block its dependent phase while independent investigation can continue.

D0 (task authority) is closed by the review’s clarification. IDs D1–D13 remain stable.

### D1 — Subscription, tenant, location and resource-group ownership

- **Blocks:** real configuration, provider plan and RG lifecycle design.
- **Options:** create dedicated RG; reference existing RG; model both through explicit mode. Tenant can be explicit non-secret config or derived from authenticated principal with expected-tenant validation.
- **Consequences:** created RG carries deletion ownership; existing RG needs scoped permissions and collision checks; supporting both adds schema/data-source branches. Region/zone determines SKU/image/HA availability.
- **Recommendation:** dedicated RG for this deployment, with an explicit `resource_group_name` in JSON for both create/reuse modes because Azure inventory needs it; environment/OIDC/CLI credentials, never credential material in JSON. User chooses actual tenancy/location.

### D2 — Azure subnet selection and the remaining AWS/GCP portability conflict

- **Blocks:** final example acceptance and Azure placement rules in T1/T3; no live address migration is necessary.
- **Established correction:** repair example reserved addresses and undersized subnet as specified in T1; retain VM key `bastion`. This does not approve changes to real configs/state.
- **Options:** (1) Azure-only IP containment selects the configured management/workload subnet without editing either existing provider; (2) fixed Azure workload placement with documented provider-specific UI address variants; (3) standardize or introduce containment in AWS/GCP as well.
- **Consequences:** option 1 accepts a valid AWS-shaped or GCP-shaped VM block unchanged on Azure, requires exactly-one-subnet validation and role-independent security rules, and avoids legacy placement changes. It does **not** make the same UI IP work across AWS and GCP: they still choose disjoint subnets by role. Option 2 narrows switching compatibility. Option 3 could satisfy strict all-three-cloud portability but expands scope and can replace an existing UI VM or its network attachment; it requires explicit approval and regression evidence.
- **Recommendation, not approval:** choose Azure-only containment and narrow example repairs. Explicitly qualify acceptance as existing AWS-or-GCP layout → Azure portability. If the task instead requires one unchanged block across all three providers, keep that requirement blocked pending an approved AWS/GCP placement change; do not claim Azure-only containment solves it.

### D3 — Alternative clouds or simultaneous topology

- **Blocks:** topology acceptance and whether preflight/schema behavior should change.
- **Options:** one cloud per deployment/state; independent clouds in separate states; a single mixed-cloud application topology.
- **Consequences:** first two fit existing deployment model; third needs cross-cloud private routing, nonoverlapping addresses, multiple bastions/inventory strategy, managed DB selection, and DNS/session/failover decisions beyond output map keys. Distinct map keys alone do not solve it.
- **Recommendation:** keep one cloud per deployment and mixed-cloud rejection, allow independent deployments in separate states with unique names/hostnames. Preserve independently selected AWS/GCP probes and budgets in the legacy root. For the proposed Azure root, recommend rejecting enabled non-Azure features; operating separate probe/budget deployments needs an approved explicit config/state strategy, not automatic root orchestration.

### D4 — Key Vault workload-secret lifecycle, least privilege and naming

- **Blocks:** T4 and the frozen T7/A2 contract; scope feasibility is a prerequisite, not something a successful `plan` proves.
- **Preferred option:** one vault, Terraform-owned non-secret URI catalog and per-(VM identity, secret) role assignments at `vault ARM ID/secrets/name`, controller-owned first real value. Confirm ARM accepts assignment before the secret exists. Catalog URI follows `https://<vault>.vault.azure.net/secrets/<name>` in public Azure, derived from the exported vault URI. Do not create workload `azurerm_key_vault_secret` resources.
- **If that gate fails:** controller creates real secrets then narrowly scoped assignments using an approved declarative grant catalog; this moves some security provisioning into Phase 2, needs privileged controller rights and explicit agreement that Phase 1 is complete without applied grants. Alternatively perform a separately authorized secret bootstrap before Terraform grant creation, with corresponding deployment-order change.
- **Rejected as a compliant fallback:** vault-wide Secrets User for every VM, including admin credentials if colocated, violates the task’s per-mapped-secret contract. It is a requirements/security downgrade, not an implementation choice. It may be reconsidered only after explicit requirement amendment; it is not recommended. Per-readership vaults are technically possible but omitted from the proposed design because this example needs five vault groups for six secrets.
- **Naming/lifecycle:** use the concrete Azure name preconditions in T4. Decide who owns deletion of controller-created secrets, soft-delete retention, recovery and purge protection; no automatic purge to make reruns convenient.
- **Recommendation:** preserve least privilege and prefer grant-before-first-version if proven. No `value`/`value_wo` placeholders: they make premature reads succeed with wrong credentials rather than fail for missing versions. Do not claim any option is approved or deployable until the capability/ownership decision closes.

### D5 — Managed PostgreSQL admin password lifecycle and state

- **Blocks:** managed DB provisioning and secret ownership.
- **Options:** GCP-like Terraform-generated stable password in protected state and Key Vault; write-only/ephemeral workflow with a persistent external source and coordinated version counters; Entra/token-based administration.
- **Consequences:** first matches existing migration contract but stores admin material in state. Write-only fields alone do not solve source persistence, rotation atomicity or secret-resource readbacks. Entra changes bootstrap/auth semantics and may require out-of-scope image/application work.
- **Recommendation:** approve GCP-like admin exception if acceptable, keeping output references only and tightly restricted state; otherwise design/review the complete write-only workflow before implementation. Do not infer a stronger no-state requirement from no-output wording or weaken an actual no-state requirement.

### D6 — Monitoring parity, retention and synthetic semantics

- **Blocks:** T1 monitoring contract and T6 acceptance.
- **Options:** all operational signals at launch; explicitly approved staged scope; native standard probes with stated limits or a custom runner for literal JSON/browser semantics. Workspace retention can use explicit shared values or an approved Azure override. Dashboard versus workbook must also be selected.
- **Concrete limits:** with the existing shared retention enum, supported Azure workspace values are **30, 60, 90, 120, 150, 180, 365, 400, 545**. Recommend explicit `30` for Azure deployments, leaving existing AWS/GCP defaults untouched. The remaining retention decision is whether that floor is acceptable or an explicit alternative storage design is required.
- **Probe consequences:** Azure standard probe intervals are 5/10/15 minutes; reject 30/60 only when an Azure probe is enabled. `runtime_version` belongs to AWS. `browser_enabled=true` requires a selected AWS browser provider or an approved custom Azure runner; Azure-only standard checks must reject it. Preserve existing combinations in the legacy root. Under D12 root isolation, an AWS browser probe for an Azure application needs a separately applied, narrowly scoped AWS/GCP-root deployment with its own config/state; the Azure root must reject an AWS probe selection rather than ignore it. Decide whether that operational split is supported in initial scope; it is not supplied by Azure module wiring. Decide whether Azure-only detailed-monitoring requests should fail or be documented as the existing AWS-only setting; no invented Azure equivalence.
- **Recommendation:** launch all agreed operational signals with fail-fast capability validation, keep 30-day Azure workspace retention explicit, and accept standard availability semantics only by decision. Reduced scope or a broader retention policy is not approved by this plan.

### D7 — AMA extension/DCR ownership

- **Blocks:** **before T6 starts**, its resource/output schema and later A4 implementation; this shifts agent installation from Phase 2 to Phase 1 relative to `azure.md` §2.1.2.
- **Options:** Terraform owns extension, DCR and associations; Terraform owns DCR/associations and Ansible controller owns extension; Ansible owns all monitoring attachment resources.
- **Consequences:** Terraform ownership gives drift/destroy control but changes reference's “Ansible installs agent” statement. Split ownership needs separate controller ARM permissions/disable cleanup. Ansible owning DCR undermines Phase 1 complete/stable infrastructure and risks dual ownership.
- **Recommendation:** Terraform owns extension/DCR/associations; Ansible prepares local files and verifies health. Obtain explicit agreement on the departure from the reference.

### D8 — PostgreSQL CA bundle delivery

- **Blocks:** complete output and database connection contract.
- **Options:** approved maintained complete bundle URL; explicit certificate-source list assembled by Ansible; host/system CA bundle mounted at existing container path.
- **Consequences:** singular URL requires an actual owner/endpoint and update process; list changes output schema but gives controlled roots; system trust broadens accepted issuers and depends on distro updates. Any approach must verify native FQDN and remain compatible with unchanged images.
- **Recommendation:** evaluate the host `ca-certificates` bundle first for the smallest operational change: verify the selected image actually contains all currently required roots, install/update it through the existing package path, and stage/mount it at the existing PEM path with checksum reconciliation. This broadens trusted issuers and requires security agreement plus an explicit Azure trust-source discriminator replacing the singular-URL requirement. If narrower trust is required, use the explicit root list and deterministic assembly. Preserve AWS/GCP URL contracts; downloading roots/package updates still requires NAT. No unsupported assertion that every Ubuntu image already has the required current bundle.

### D9 — Budget scope/dates/currency and controller vault access

- **Blocks:** budget schema/resource selection and vault network policy.
- **Options:** subscription-wide budget or RG deployment budget; explicit first-of-month date or separate lifecycle owner; public vault with firewall/RBAC or private endpoint with routed controller.
- **Consequences:** subscription budget counts unrelated spending; RG budget is narrower than AWS's account scope. Currency comes from Azure billing, not an arbitrary resource argument; dates and notification constraints require fields beyond the proposed AWS shape. Private vault can block operator uploads/plans without controller routing.
- **Recommendation:** RG budget for a dedicated RG, explicit stable date and billing-currency check, absolute→percent conversion; choose controller reachability before enforcing vault network restrictions. Public authenticated access versus private networking remains a security/product choice.

### D10 — Bootstrap SSH and required Azure VM admin user

- **Blocks:** usable first-boot deployment and exact VM schema.
- **Options:** cloud-init sets configured bastion port before Ansible; explicitly temporary restricted port-22 rule and two-stage bootstrap; require bastion port 22 initially. Azure admin user can be explicitly selected from `ssh_users` or chosen by a documented derivation.
- **Consequences:** custom-data change may replace VM; temporary rule needs cleanup/approval sequencing; requiring port 22 edits neutral configuration. Arbitrary sorted-user selection is an implicit policy and can change on a new key entry.
- **Recommendation:** explicit Azure admin user referencing existing `ssh_users`, provision all users via cloud-init, configure bastion SSH port at first boot. Do not open public 22 permanently or assume existing AWS/GCP bootstrap is a working pattern for 8787.

### D11 — Economy profile, images, HA, backup/destruction policy

- **Blocks:** concrete examples and supported Azure resource choices.
- **Options:** paid low-cost dev profile; target available subscription credits/free offer; production availability profile. Choose exact image version, PostgreSQL major/SKU/storage/HA and minimum backup retention, and whether managed DB destruction intentionally discards retained data.
- **Consequences:** Azure minimum retention is seven days; RDS economy profile is not transferable. Burstable capacity may not support HA; History needs RabbitMQ/OS/agent memory headroom. Current docs permit PG18 but target subscription/region/provider release must agree. Image minimum disk may conflict with 10 GiB.
- **Recommendation:** explicit low-cost development profile without a free-tier promise, PG18 if actually available and compatible with existing image/SQL, HA disabled only by an approved explicit profile. Preserve established fresh-data mode-switch semantics only after documenting Azure retention/soft-delete behavior.

### D12 — Technical diagnostic closed; root-isolation approval required before T1

- **Status and blocker:** the follow-up reviewer’s AzureRM v4.63 diagnostics resolve the tested inactive-graph question (§15.2). The architecture choice remains unapproved and blocks T0 completion, T1/T2 and compatibility acceptance.
- **Evidence:** an unused provider-only declaration was pruned and planned successfully. Zero-count Azure resources, including inside a zero-count module, still attempted authentication; a placeholder subscription did not help. Dummy service-principal values with registration disabled still triggered a real Entra token request. Credential-free `validate` succeeded, so current CI’s static checks cannot prove operator-plan compatibility. These are results for the reported version/graphs, not a claim about all future releases.
- **Specification conflict:** `azure.md` §1.4 item 4 requests Azure modules in the existing `TF/main.tf`; §1.6 requires unchanged existing AWS plans. The tested same-root approaches cannot satisfy both without new Azure authentication. Requiring a subscription field, an all-zero GUID or module `count=0` is not a surviving remedy.
- **Available options and consequences:** (1) approve a separate Azure root, recommended path `TF/azure`, reusing shared JSON schema and appropriate modules and exporting the same Ansible contract; preserve the legacy resource graph, lockfile and state, but change Azure entrypoint/backend/CI/docs and explicitly approve the same-root provider/module/output requirements exception (§1.4 items 2, 4 and 5). (2) retain same-root Azure modules and explicitly accept Azure authentication for existing AWS/GCP plans; this breaks compatibility and requires changing §1.6, operator prerequisites and acceptance criteria. Neither option is already approved.
- **Recommendation:** approve option 1. T2 describes the concrete root/state contract, T7/§6 the output contract, and DOC1 the operating commands. Do not wrap the old root, use credential workarounds or perform state migrations. Cross-root probe/budget policy must close under D3/D6.
- **Exit evidence:** written architecture decision plus implementation checks showing the legacy dependency graph excludes Azure and semantically unchanged AWS/GCP plans with no Azure credentials. Revisit the diagnostic only if a different provider release or materially different proposed graph could alter it; do not repeat it merely to keep an already tested workaround open. Isolate CLI cache and environment for validation; never clear the operator’s real session.

### D13 — Live acceptance authorization

- **Blocks:** live A5 validation and final supported-deployment claim, not static implementation or a new test-policy decision.
- **Options:** deliver static/schema/plan evidence with runtime gates pending; separately authorize a scoped Azure deployment and one old-cloud regression deployment.
- **Consequences:** no plan can prove boot, scoped Key Vault reads, private DNS/TLS, telemetry or an Ansible recap. Existing CI has no Terraform test files; its `terraform test` invocation is not an unresolved policy conflict. No automated tests are added by this plan.
- **Recommendation:** complete design/static/plan work first, then obtain explicit live scope, cost and cleanup authorization. Historic AWS permissions do not authorize Azure apply, destructive reset or production failure injection.

## 15. Review disposition and revision evidence

This section explains why V2 adopts, qualifies or rejects each numbered finding. It is part of the design handoff: do not reintroduce an unsupported remedy solely because it appears in the review checklist.

| Review item | Disposition | V2 action / qualification |
| --- | --- | --- |
| C1 — inactive provider/subscription | **Technical diagnostic resolved; architecture approval pending** | Follow-up v4.63 results reject the tested GUID/count/module-count remedies. D12 recommends a separate Azure root with explicit specification exception; T0/T1 remain gated on that approval. |
| H1 — mixed image types | **Technical premise rejected** | Preserve structured Azure image and split JSON schema. Terraform object comprehensions allow heterogeneous values; the review’s claimed automatic unification error is false. Homogeneous-map conversions would be a different failure. |
| H2 — uploader false success | **Accepted; independently fixable** | Optional separately scoped maintenance fix can add an AWS/GCP-only guard before Azure review; otherwise A2 owns it. Azure upload implementation still waits for Phase 1 review (§9). |
| H3 — Key Vault lifecycle | **Accepted with security correction** | Single-vault catalog preferred; remove operationally expensive multi-readership-vault fallback from proposed design. Explain wrong-value placeholder failure. Vault-wide reads are not a compliant fallback; controller-scoped grants require explicit ownership/sequencing approval. |
| H4 — GCP budget metadata | **Accepted** | T1 explicitly retains disabled AWS/GCP budgets and both region branches in Azure acceptance inputs. No speculative GCP refactor. |
| M1 — retention intersection | **Accepted** | Nine concrete values, proposed 30-day Azure setting, workspace-enabled validation; do not alter legacy defaults. |
| M2 — synthetic settings | **Accepted with feature-selection qualification** | Add Azure enum and 5/10/15 restriction for active Azure standard probes. Preserve independent AWS browser probes; no blanket rejection merely because application VMs are Azure. |
| M3 — inventory options | **Preferred option mapping accepted; categorical absence claim corrected** | Use Azure-specific hostvars/groups/filters; current docs expose `compose` and `groups` too. Preserve safe defaults. Include filters are ORed, so combine intended restrictions in one AND expression. Plain host names are presentation, not the secret-identity authority. |
| M4 — migration dispatch/decoding | **Accepted** | A3 returns raw secret strings, explicitly guards cloud dispatch, and names the undefined-GCP-register failure mode. |
| M5 — agent disable path | **Accepted** | Explicit first A4 change; prevent Azure disable from taking GCP paths. Terraform-managed extension lifecycle remains single-owner. |
| M6 — names/deletion | **Accepted with lifecycle qualification** | Concrete name validation and Key Vault lifecycle guidance. Do not automatically disable purge protection or assert Flexible Server has Key Vault’s same retention/name-reservation contract. |
| M7 — PostgreSQL subnet | **Accepted with precise prefix wording** | Proposed dedicated `10.0.3.0/28`; prefix length <=28, not “>= /28” interpreted numerically; containment/nonoverlap and exclusive service use checked. |
| M8 — Cloudflare coalesce | **Accepted** | Input and map entry required; missing-address handling should reach intended diagnostics. Record missing existing proxy validation rather than claiming it is enforced. |
| L1 — CI test policy | **Accepted** | No Terraform test files found; remove policy-conflict decision, retain no-new-tests rule. |
| L2 — authority | **Accepted** | Name `azure.md` as specification, close D0. |
| L3 — bastion key | **Accepted** | Preserve literal VM key `bastion` in examples. |
| L4 — lockfile | **Accepted with precision** | Registry checksums and developer/Linux verification required. A single-platform-only `h1:` is the portability risk; multiple platform hashes can also support portability. |
| L5 — provider-source rationale | **Accepted** | Keep explicit Azure child requirements while correcting the implied default-namespace necessity. |
| Missing impacts 1–5 | **Accepted** | Collection dependency metadata, maximum Ansible floor, conditional Python 3.12 fallback at both Ansible CI settings, four inventory-doc sections, mandatory Azure SSH key setup. |
| Missing impact 6 — trust store | **Recommendation updated, approval retained** | Evaluate host trust-store strategy first for lower operational complexity, require actual root verification and acceptance of broader trust. Explicit root list remains narrower alternative. |
| Missing impact 7 — preflight | **Accepted** | Existing preflight is cloud-neutral; leave unchanged unless a demonstrated integration issue or approved topology decision requires change. |
| Example-state finding | **Accepted in scope, corrected in provenance** | State is local/untracked, not tracked; addresses were inspected narrowly. Reserved-address repair affects examples only, but shared UI placement remains unresolved. |
| Byte comparison in checklist | **Corrected** | Compare semantic resource plans under fixed inputs/state/versions; byte equality is not a meaningful infrastructure compatibility criterion. |

### 15.1 Terraform typing diagnostic — executed

In an empty temporary directory, using local Terraform **1.15.8**, the following console-only expression exited successfully:

```hcl
type({
  for k, v in {
    aws   = "ami-reference"
    azure = { publisher = "Canonical", offer = "ubuntu", sku = "server", version = "latest" }
  } : k => { native_image = v }
})
```

The result was an object with `aws.native_image: string` and `azure.native_image: object(...)`. No provider, project config, state, cloud API or production file was involved. This directly disproves H1’s expression-level claim; it does **not** prove full Azure module plans. HashiCorp documents that braces in a `for` expression produce an object, with conversions imposed by the receiving context where needed. [Terraform for expressions](https://developer.hashicorp.com/terraform/language/expressions/for)

### 15.2 Provider compatibility evidence — reviewer-executed diagnostics

The follow-up review supplied with this revision reports isolated **AzureRM v4.63** diagnostics with no `ARM_*` credentials and an empty temporary `AZURE_CONFIG_DIR`. These results were supplied by the reviewer, not independently executed during this edit; raw plans/lock artifacts were not attached and the reviewer reports deleting the scratch provider download. Do not infer a production version pin or full repository integration proof from them.

| Reported graph / operation | Reported result | Design implication |
| --- | --- | --- |
| Provider declaration only, no Azure resources; plan | Success; unused provider pruned | Provider-only success does not prove empty-resource graph compatibility. |
| `azurerm_resource_group` with `count=0`; plan | Unable to build Resource Manager authorizer | Zero instances still configure the provider in this graph. |
| Same graph plus placeholder subscription GUID; plan | Same authentication failure | An ID does not remove authentication. |
| Azure resource inside a module with `count=0`; plan | Same authentication failure | Module count is not the required isolation. |
| Nonfunctional service-principal values, registration disabled; plan | Entra request failed with `AADSTS700038` | Disabling registration does not disable token acquisition; dummy credentials are not a solution. |
| Zero-count graph; validate | Success without credentials | Static CI success does not establish credential-free plan behavior. |

The reviewer reports no resource mutations; the token-request case did contact Entra. Existing fixed-source inspection of AzureRM v4.63.0 is consistent with these observations: subscription checking precedes authenticated client construction. [AzureRM source](https://github.com/hashicorp/terraform-provider-azurerm/blob/v4.63.0/internal/provider/provider.go)

**Disposition:** close D12’s technical diagnostic for the tested version/graphs, reject the tested same-root workarounds, and request architectural approval for root separation. Validate the actual implementation with its selected release; neither source inspection nor these scratch graphs replace legacy baseline comparison. Current CI runs fmt/init/validate/test, with no Terraform test files, so it does not currently encounter this operator-plan authentication failure. Once a second root is introduced, CI must explicitly initialize/validate that root too.

Earlier V1/V2 documentation research used Context7 and primary sources. No provider init/plan/authentication diagnostic was newly run by the plan editor in this revision.

### 15.3 Inventory source check

Current generated docs include `compose`/`groups` as well as Azure-specific options. Current plugin source explicitly falls back from `hostvar_expressions` to `compose`, uses `conditional_groups`, and matches include filters with OR semantics. Hence the review’s suggested Azure option family is useful, but its claim that `compose` is absent is false. Confirm the chosen release’s exact option/host-variable names before implementation. [Azure inventory documentation](https://docs.ansible.com/projects/ansible/latest/collections/azure/azcollection/azure_rm_inventory.html), [inventory implementation](https://github.com/ansible-collections/azure/blob/dev/plugins/inventory/azure_rm.py)

### 15.4 Additional source and repository evidence

- AWS also reserves the first four and final addresses; its IPv4 subnets cannot be smaller than `/28`. Thus the examples’ `/29` management subnet is an existing AWS defect as well as their reserved addresses. The proposed `/24` example repair addresses this; it does not authorize network replacement. [AWS subnet sizing](https://docs.aws.amazon.com/vpc/latest/userguide/subnet-sizing.html)
- Dedicated PostgreSQL VNet integration has a `/28` minimum and provider/service-specific network dependencies. Validate the full selected configuration rather than reusing the workload subnet. [Azure PostgreSQL private networking](https://learn.microsoft.com/en-ca/azure/postgresql/network/concepts-networking-private)
- Key Vault identifiers are case-insensitive; object names permit 1–127 letters, digits and hyphens. Recovery/purge protection requires its own operator procedure. [Key Vault identifiers](https://learn.microsoft.com/en-us/azure/key-vault/general/about-keys-secrets-certificates), [soft delete](https://learn.microsoft.com/en-us/azure/key-vault/general/soft-delete-overview)
- Flexible Server has a documented dropped-server recovery procedure within five days, recommending a different restore name to avoid DNS issues. That does not establish the review’s implied equivalence with vault-name reservation for 7–90 days. Do not promise either guaranteed immediate reuse or identical retention periods; verify the selected server’s lifecycle behavior before approving destructive acceptance. [Deleted-server recovery](https://learn.microsoft.com/en-us/azure/postgresql/backup-restore/how-to-restore-deleted-server)
- Registry-backed provider locking supports explicit platform checksums. Preserve existing constraints and include the CI platform when recording the Azure entry. [Provider lock command](https://developer.hashicorp.com/terraform/cli/commands/providers/lock)
- Repository inspection confirmed `galaxy.yml` cloud dependencies, both Python 3.14 settings in the Ansible CI job, GCP budget’s unconditional read, the Cloudflare empty-`coalesce` expression, zero Terraform test files, and the locally recorded nonreserved deployment IPs. No full state, secret payloads or credentials were copied into this plan.

### 15.5 Follow-up review disposition

- **D12 evidence:** accepted with attribution and version/graph scope. The technical unknown is closed; the specification exception remains an owner decision. Root separation is propagated through file ownership, provider locks, backend/state isolation, feature selection, outputs, CI and operating documentation.
- **D2 containment:** accepted as the recommended Azure-only implementation. Correct the review’s broader implication: it allows Azure to consume either existing layout, but does not resolve the unchanged AWS-versus-GCP UI-subnet mismatch.
- **H2 ordering:** accepted as a possible independent legacy bug fix. It does not authorize Azure Ansible implementation before Terraform review or production edits during this task.
- **H1 corroboration:** the follow-up reviewer also reports a successful repository-shaped heterogeneous-object/filtered-AWS-resource plan, including object-valued Azure images and `values(image_map)` validation. This supports retaining the object contract; it is additional reviewer evidence, not a plan run performed here.

### 15.6 Final four-item review disposition

1. **Mandatory legacy-entrypoint guard — accepted.** Source inspection confirms Azure-selected VM maps can be empty while legacy outputs index `bastion` and workload keys. This is a reasoned failure path, not a newly executed legacy-root plan, and independent budgets/probes can still be enabled: do not generalize it to every module always gating to zero. T2 now requires blocking validation ahead of unsafe evaluation and verification of its actual ordering. A `check` warning is insufficient. [Terraform validation behavior](https://developer.hashicorp.com/terraform/language/validate).
2. **Complete Azure-root providers — accepted with a technical qualification.** Shared Cloudflare constraints, explicit root configuration, lock-version parity checks and conditional Random requirements are now specified. Terraform can synthesize an empty default provider configuration; omission of the explicit block is not by itself proof that DNS lacks one. The missing root version constraint is a real independent-root gap.
3. **New-root variables — accepted.** Require explicit configuration path without a workstation default; exclude the GCP writer variable and defer any Azure equivalent to D4.
4. **Acceptance wording — accepted.** The Azure-plan row now distinguishes shared-schema requirements from optional disabled-budget hygiene, consistent with T1. Existing closed schema definitions must explicitly admit Azure while preserving their AWS/GCP requirements.

This revision checked repository declarations and current HashiCorp documentation (Context7 plus primary pages). No Terraform init/plan, production changes or cloud operations were performed.
