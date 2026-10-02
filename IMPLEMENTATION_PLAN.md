# k3s deployment implementation plan

Status: proposed implementation; no infrastructure has been provisioned or changed.

## Target outcome

Deploy OilScope to exactly three Kubernetes VMs in the selected cloud. Each VM runs a k3s server, embedded etcd, and application workloads, and has both `control plane` and `worker` role tags in JSON. There is no bastion or separate application, broker, cache, database, or etcd VM. Ansible runs from the operator's local machine; Helm releases are installed and managed from that same machine.

Managed PostgreSQL is the initial deployment default. Keep the existing `managed_database` boolean: `true` selects the cloud database; `false` selects PostgreSQL inside Kubernetes. Both paths must ultimately work without adding another VM.

Publish and pull application images through the selected cloud's native image registry instead of GHCR: Amazon ECR for AWS, Google Artifact Registry for GCP, and Azure Container Registry (ACR) for Azure.

This document plans the implementation requested; it does not execute a deployment.

## Existing code and required changes

| Area | Current behavior | Planned change |
| --- | --- | --- |
| `project-config*.json` | Bastion and service-specific VMs; broker/cache reference `host_vm` | Three Kubernetes VMs; move application settings and secret references outside VM definitions |
| `infrastructure/terraform/project-config.schema.json` | Requires bastion and service roles; unmanaged DB requires a database VM | Add a k3s configuration branch with three dual-role nodes and both DB modes |
| `infrastructure/terraform/modules/{aws,gcp,azure}/` | VM roles drive networking, identity, database access, DNS and monitoring | Support Kubernetes nodes, role metadata, optional public IPs and cluster endpoints |
| `infrastructure/ansible/oilscope/platform/plugins/` | Inventory connection helper expects a bastion and SSH proxy | Direct public/private SSH and overlapping control-plane/worker groups |
| `playbooks/deploy_workloads.yml` and deployment roles | Docker Compose on individual hosts | Add k3s bootstrap and local Helm deployment path |
| Database connection/migration roles | Managed DB TLS and grants already implemented | Reuse connection contract and SQL in a Kubernetes migration Job |
| UI Redis client | Uses a single Redis URL | Start with standalone persistent Redis; do not assume Sentinel discovery already works |
| Monitoring and CI | VM/Compose assumptions | Add Kubernetes health checks, chart checks, cluster-specific validation and documentation |

Paths for playbooks and roles above are relative to `infrastructure/ansible/oilscope/platform/`. Preserve local Compose development. Isolate the new deployment branch using `deployment_target: "k3s"` so an existing deployment is not silently converted by a routine redeploy.

## 1. JSON configuration contract

Keep provider, region, image/size maps and database profile settings. Replace GHCR-specific registry configuration with cloud-native registry settings derived from `default_cloud`, including repository names, location and immutable image references. Only the `vms` map describes machines; Kubernetes workloads do not need VM entries. The following is a proposed configuration fragment, not a complete file accepted by today's schema:

```json
{
  "deployment_target": "k3s",
  "managed_database": true,
  "database_profile": "economy",
  "vms": {
    "k3s-1": {
      "role": "kubernetes",
      "tags": ["control plane", "worker"],
      "size": "kubernetes",
      "image": "ubuntu-26.04",
      "disk_type": "ssd",
      "disk_size_gb": 60,
      "internal_ip": "10.0.1.21",
      "assign_public_ip": true
    },
    "k3s-2": {
      "role": "kubernetes",
      "tags": ["control plane", "worker"],
      "size": "kubernetes",
      "image": "ubuntu-26.04",
      "disk_type": "ssd",
      "disk_size_gb": 60,
      "internal_ip": "10.0.1.22",
      "assign_public_ip": true
    },
    "k3s-3": {
      "role": "kubernetes",
      "tags": ["control plane", "worker"],
      "size": "kubernetes",
      "image": "ubuntu-26.04",
      "disk_type": "ssd",
      "disk_size_gb": 60,
      "internal_ip": "10.0.1.23",
      "assign_public_ip": true
    }
  },
  "kubernetes": {
    "ssh_address_mode": "public",
    "admin_allowed_cidrs": ["192.0.2.10/32"],
    "api_endpoint": "api.oilscope.example.com",
    "api_endpoint_mode": "cloud_load_balancer",
    "pod_cidr": "10.42.0.0/16",
    "service_cidr": "10.43.0.0/16",
    "namespace": "oilscope",
    "etcd": {
      "snapshot_schedule_cron": "0 */6 * * *",
      "snapshot_retention": 28,
      "backup_destination": "cloud_object_storage"
    }
  },
  "ingress": {
    "endpoint_mode": "cloud_load_balancer",
    "hostname": "oilscope.example.com",
    "acme_email": "operator@example.com",
    "acme_environment": "staging",
    "challenge_type": "http01"
  }
}
```

Implementation requirements:

- Add a dedicated `kubernetes` size-map entry, initially targeting at least 2 vCPU / 8 GiB per node; validate actual provider sizing and capacity under one-node loss. Existing `micro` examples are unsuitable for this combined workload. Pin and verify the OS/k3s combination before deployment.
- Require exactly three unique VM names and private addresses, both tags per VM, one cloud and one region per cluster. Where supported, distribute nodes across three availability zones and create corresponding subnets. Do not stretch etcd across clouds.
- Preserve literal JSON tags. Normalize `control plane` to `control-plane` for provider constraints, using provider tags/labels such as `oilscope-control-plane=true` and `oilscope-worker=true`. Apply Kubernetes role labels separately. Tags express membership; they do not install services by themselves.
- Keep `assign_public_ip` per VM. Add an optional provider-specific reserved-address reference for attaching an existing public IP; do not accept arbitrary unowned IP strings. Export allocated addresses through Terraform.
- Require direct SSH reachability to every node: public IP mode or a pre-existing VPN/private route. Reject public mode when a node lacks a public address. Private nodes also need outbound access to registries and package sources, through NAT or another explicit route.
- Move `public_endpoint`, workload secret mappings, and RabbitMQ/Redis settings to cluster/application configuration. Remove `host_vm` requirements in k3s mode.
- Preserve `managed_database` as the single DB selector. Validate all examples and both branches before provisioning. Commit secret identifiers only, never secret values.

## 2. Terraform: nodes, networking and endpoints

1. Update the root normalization, schema and AWS/GCP/Azure VM, network, database, secrets and monitoring modules for `deployment_target`.
2. Provision only the three configured VMs. Remove bastion resources, bastion startup installation, proxy access assumptions and dedicated workload IP rules from the k3s branch.
3. Add normalized outputs for node identity, roles, public/private addresses, SSH settings, API endpoint, ingress endpoint, database connection metadata and backup destination. Ansible must consume outputs rather than guess addresses.
4. Allow SSH and Kubernetes API access only from configured administrator CIDRs/private management networks. Allow TCP 6443, TCP 2379–2380, TCP 10250 and the selected overlay traffic between appropriate nodes; Flannel VXLAN uses UDP 8472. Keep etcd and overlay traffic private. Allow public 80/443 only at the application entry point. Verify the final matrix against the pinned k3s networking configuration.
5. Restrict managed PostgreSQL access to cluster-origin traffic; account for pod egress SNAT and provider routing. Keep broker/cache and service APIs private.
6. Provide health-checked cloud load balancers for API TCP 6443 and ingress TCP 80/443, without extra VMs. Use separate listeners/endpoints so application exposure does not expose administrative access. Provision provider-specific target groups, probes, firewall rules and DNS in Terraform rather than assuming a Kubernetes `LoadBalancer` Service automatically creates cloud resources.
7. Offer a lower-cost explicit `node` endpoint mode using a designated node address. Document that this endpoint fails when that node fails even though etcd retains quorum. DNS round-robin alone is not automatic health-checked failover. Do not assume a floating layer-2 IP works across cloud subnets.
8. In load-balancer mode, use fixed ingress NodePorts targeted by the cloud LB and allow those ports only from the LB's required sources. Support direct-node ingress through an explicit host-port configuration for node mode.

References: [k3s networking requirements](https://docs.k3s.io/installation/requirements), [HA embedded etcd](https://docs.k3s.io/datastore/ha-embedded).

## 3. Ansible: bootstrap three dual-role nodes

Add `playbooks/bootstrap_k3s.yml`, `playbooks/deploy_k3s.yml`, and focused roles for preflight, server installation, local kubeconfig, platform releases, secrets, migrations and application deployment.

1. Update inventory plugins and `oilscope_inventory.py` to form `k3s_servers` and `k3s_workers`, with all three hosts in both groups. Connect directly with verified SSH host keys; retain privilege escalation for host setup.
2. Preflight validates the complete topology, routes, DNS, CIDR overlap, disk capacity, local tool versions, image access and required secret references before changes. Preserve the wrapper's zero-host protection and also detect accidentally skipped node or localhost phases under `--limit`.
3. Install a pinned k3s release with its containerd runtime; reuse appropriate host-baseline tasks without installing Docker for Kubernetes workloads. Write consistent server configuration on all nodes.
4. Initialize `k3s-1` once with `cluster-init`. Join `k3s-2` and `k3s-3` as **servers**, sequentially, using the private bootstrap address and shared protected token. Wait for readiness and etcd membership before each join. Existing cluster state must prevent reinitialization on reruns.
5. Keep the server agent enabled so every server runs workloads. Do not add a control-plane `NoSchedule` taint for this topology. Add both role labels and verify an ordinary workload can schedule on every node.
6. Configure private node/advertise addresses, shared network settings, API endpoint TLS SANs and Kubernetes secrets encryption. Disable bundled Traefik and ServiceLB because this plan explicitly manages ingress with local Helm and Terraform load balancers.
7. Fetch kubeconfig to an ignored local file with mode `0600`, retaining CA verification and replacing its loopback address with the configured reachable API endpoint. Use an explicit context/path for every local Helm operation; do not overwrite the user's default context. Document credential rotation and avoid printing admin credentials.
8. Use serial one-node maintenance, health gates and a pre-upgrade snapshot for upgrades. Never restart all three servers together during ordinary upgrades.

The server bootstrap and common configuration requirements follow the [k3s embedded-etcd HA documentation](https://docs.k3s.io/datastore/ha-embedded).

## 4. Embedded etcd and recovery

Use k3s-managed embedded etcd: one member per server, three members total. Majority quorum is two, allowing one failed node. Do not deploy etcd through Helm or use the application PostgreSQL instance as the Kubernetes datastore.

Use SSD-backed storage, reserve resources for system components, and set pod requests/limits to avoid broker/app activity starving etcd. Schedule snapshots every six hours with 28 local snapshots retained per server. Copy backups off-node into a private provider object store with encryption and retention, and monitor failures and snapshot age.

Use native k3s S3 backup where the destination is supported. For GCS/Azure Blob, implement a provider-native upload/retention task rather than assuming an S3-only configuration supports every provider. Store and back up the server token separately; it is required to recover encrypted bootstrap data. Never put it in JSON or Git.

Provide a separate, explicitly invoked recovery playbook/runbook: stop servers, restore a chosen snapshot on one member, rebuild membership by rejoining the other servers, and verify API and workloads. Ordinary deployment must never run a cluster reset. Test restoration on a disposable cluster. Etcd snapshots do not back up PostgreSQL, RabbitMQ or Redis volume contents; those need separate backups.

References: [k3s backup and restore](https://docs.k3s.io/datastore/backup-restore), [etcd snapshot management](https://docs.k3s.io/cli/etcd-snapshot).

## 5. Local Helm and certificates

Add `infrastructure/helm/` containing application charts, platform values, and a version manifest. Pin chart and container versions after compatibility and registry-pull checks; do not use floating `latest` versions.

Run all Helm tasks in Ansible plays with `hosts: localhost`, local connection and no privilege escalation. Add compatible, pinned `kubernetes.core` and Python Kubernetes dependencies plus a documented local Helm/kubectl setup. Use the generated kubeconfig explicitly. The cluster runs the deployed services, while Helm execution stays on the laptop.

Release ordering:

1. Install Traefik through its upstream Helm chart with ingress replicas spread across nodes and the exposure settings selected in Terraform.
2. Install cert-manager once as a separate Helm release from `oci://quay.io/jetstack/charts/cert-manager`, including its CRDs. Wait for CRDs, controllers and webhook readiness before creating issuers.
3. Create separate Let's Encrypt staging/production ClusterIssuers and a UI Certificate/Ingress using the explicit Traefik ingress class. Use HTTP-01 by default: public DNS and port 80 must route to the solver. Validate staging before switching configuration to production. Allow DNS-01 when private ingress or wildcard certificates require it, with narrowly scoped DNS credentials.
4. Set the application ingress TLS Secret and secure UI session cookies. Remove the VM edge proxy's independent ACME ownership in the Kubernetes path.
5. Verify certificate readiness, browser trust in production, renewal and ingress availability after a node failure. Keep issuer account keys across redeployments.

Internal service DNS names require an internal CA rather than public Let's Encrypt certificates. Use cert-manager's CA issuer for broker/cache TLS and distribute its trust bundle to clients; keep that CA's key in protected secret storage.

Reference: [cert-manager Helm installation](https://cert-manager.io/docs/installation/helm/).

## 6. RabbitMQ, Redis and persistence through Helm

Install RabbitMQ and Redis as separate Helm releases. Select maintained charts only after checking licensing, image availability without unexpected subscriptions, supported versions, TLS and existing-secret support. If suitable maintained charts are unavailable, provide small repository-owned charts using supported upstream images. Record the selected sources and versions in the version manifest before implementation is considered complete.

- **RabbitMQ:** target three broker replicas spread across nodes, persistent volumes and quorum queues. Preserve current exchange, routing, main/retry/dead-letter topology, outbox behavior, credentials, memory limits and delivery policies. Verify the exact retry/dead-letter policy compatibility. Configure peer discovery, stable identities and a shared protected Erlang cookie. Use verified AMQPS with DNS SANs matching the client Service endpoint. Test publisher/consumer reconnection on broker failure; three broker pods alone do not make non-replicated queues resilient.
- **Redis:** initial baseline is one persistent standalone instance using the existing URL-based client. Retain authentication, session TTL/key prefix and persistence. Use verified TLS because clients can now be on another node. Explicitly document the interruption during Redis rescheduling; k3s control-plane HA does not make this single-instance service continuously available. Sentinel is a later HA option requiring client discovery/configuration and failover tests, not just a replica-count change.
- **Storage:** install/configure the selected cloud's CSI driver and identity permissions; select an encrypted expandable storage class with topology-aware binding. Do not depend on k3s local-path volumes for recoverable cloud deployment. Account for zonal disk attachment: pod rescheduling does not guarantee cross-zone volume recovery. Use anti-affinity, suitable disruption budgets, explicit retention and backup/restore procedures. RabbitMQ replication and Redis backups solve different failure cases.
- Expose both services only inside the cluster. Preserve credentials and volumes during upgrades; do not generate replacement passwords or reset data on each run.

References: [RabbitMQ clustering](https://www.rabbitmq.com/docs/clustering), [Redis Sentinel and client requirements](https://redis.io/docs/latest/operate/oss_and_stack/management/sentinel/).

## 7. Managed database first, configurable self-hosting

1. Retain existing AWS RDS, GCP Cloud SQL and Azure Flexible Server modules and database profile maps. Refactor their dependencies on History/Fetcher VM roles to use cluster identity and network outputs.
2. Preserve verified TLS, provider CA handling and separate application credentials from the existing database connection roles. Private database DNS must resolve from pods. Managed database availability remains determined by its profile; an economy single-zone DB is not made HA by this cluster.
3. Move schema initialization, role/grant setup and existing migrations into a controlled Kubernetes Job that completes before application rollout. Reuse `database/migrations/` and the current migration runner. Keep privileged migration credentials separate from runtime secrets; prevent concurrent migration runs and fail deployment on errors.
4. For `managed_database: false`, disable cloud DB creation and deploy PostgreSQL inside the existing cluster with a persistent volume and backups. Provide the same connection contract to applications; no fourth VM and no silent fallback to managed mode. Implement after the managed path, but keep it in the completion criteria. During intermediate development, fail clearly if this branch is not implemented.
5. Treat changes to the boolean on an existing deployment as a separate data migration/cutover operation. Do not automatically destroy the previous DB, purge messages/sessions or suggest switching back restores data. Document backup, transfer, verification and rollback before applying a mode change.

## 8. Application chart and secrets

Create `infrastructure/helm/oilscope/` for History, Fetcher and UI Deployments, ClusterIP Services, ConfigMaps, secret references, ingress, probes, resource settings and scheduling policies. Reuse the existing Dockerfiles, and modify the image publication workflows to publish to the selected cloud-native registry. Deploy immutable image digests from that registry.

### Cloud-native image publishing and pulling

- Terraform provisions private application repositories in Amazon ECR, Google Artifact Registry or Azure Container Registry according to `default_cloud`, with lifecycle/retention settings and outputs for repository URLs. Support referencing an existing registry explicitly. Preserve deployed and rollback image digests when applying retention policies.
- Update `.github/workflows/publish-images.yaml` and `.github/workflows/reusable-build-image.yaml` to authenticate to the selected cloud, build and push Fetcher, History, UI and any migration image, and expose immutable digests for deployment. Prefer GitHub Actions OIDC federation with narrowly scoped publish permissions; avoid long-lived cloud credentials.
- Configure authenticated pulls on every k3s node using a provider-supported kubelet credential provider or an explicitly managed, renewable pull-secret mechanism. Verify support for the pinned k3s release; do not assume integrations supplied by managed Kubernetes services also exist on these VMs. Grant pull-only access to runtime identities and handle token refresh automatically.
- Update JSON examples, schema, Terraform outputs, Ansible preflight, Helm image references and documentation to use native repository addresses. Remove `GHCR_TOKEN` and GHCR username/repository requirements from the k3s application deployment path. Keep secret values out of JSON and Terraform outputs.
- Support authenticated local publishing for operators as well as CI publishing. Document registry connectivity for private nodes, including provider endpoints or outbound routing where needed.
- Application images must be pushed to and pulled from the native registry. Third-party platform images and build base images may retain their upstream sources; if those must also use the native registry, add explicit mirroring and digest tracking.
- Validate fresh-node pulls, credential refresh, image rollout and rollback using each supported cloud's registry. A cached image must not hide broken authentication.

Use Kubernetes service DNS for History, RabbitMQ and Redis. Start with two UI/History replicas after confirming concurrent consumer behavior. Keep Fetcher at one replica with a `Recreate` rollout strategy because its current process owns the schedule and startup fetch; avoid overlapping schedulers until leader election or a separate scheduling design is implemented.

Port existing environment variable contracts and CA mounts. Separate dependency readiness from process liveness so a temporary DB/broker failure does not create cascading restarts. Include graceful termination for in-flight consumer work and topology spread for replicated workloads.

Resolve existing cloud secret identifiers locally using the operator's cloud identity and create namespace-scoped Kubernetes Secrets with `no_log` protection. Move away from VM-attached secret files and per-service VM identities in this path. Restrict pod service accounts/RBAC, prevent secret values appearing in Helm values/output, and document rotation. Use network policies that allow DNS and required application, database and ACME traffic.

## 9. Delivery sequence and validation

1. **Config and infrastructure:** schema/examples, normalized outputs, direct inventory, three-node Terraform plans for each supported cloud, managed database defaults, optional public addresses, and native registry provisioning with CI push/node pull permissions.
2. **Cluster:** bootstrap, local kubeconfig, etcd health, protected backups and restore procedure.
3. **Platform:** storage driver, local Helm execution, ingress, cert-manager, RabbitMQ and Redis.
4. **Application:** managed database migration Job, Secrets, application chart and HTTPS end-to-end test.
5. **Alternative DB:** implement and test `managed_database: false` on the same three-node topology.
6. **Operations:** upgrades, monitoring, documentation and controlled migration from the existing Compose deployment.

Update `.github/workflows/pr-validation.yml` and add focused tests for schema/topology rejection, tag translation, direct inventory connections, no-bastion operation, endpoint selection, secret redaction and both DB modes. Run Terraform formatting/validation, Ansible lint/syntax checks, Helm lint/template checks and Kubernetes manifest validation against the pinned release.

On disposable cloud infrastructure verify:

- Exactly three Ready nodes, each with both roles and schedulable workloads; three healthy etcd members.
- Local Helm can list, install and upgrade releases using the generated context.
- CI and local publishing push application images to the selected native registry; fresh nodes pull the pinned digests successfully and continue pulling after credential renewal, without GHCR credentials.
- Invalid/unreachable public/private address combinations fail before deployment.
- No bastion or workload-specific VM is created; no broker/cache/etcd public port is exposed.
- Database initialization and a Fetcher → RabbitMQ → History → UI flow succeed with persisted observations and sessions.
- Production HTTPS is valid after staging succeeds; certificate renewal is exercised.
- Re-running deployment preserves tokens, passwords, PVCs and data and does not reinitialize etcd.
- Stopping one server retains quorum and load-balanced API/ingress access; RabbitMQ quorum queues continue operating. Measure and document Redis recovery separately.
- Etcd restore and stateful-service restores work from off-node backups.
- Both database modes work; changing modes requires the documented cutover rather than incidental recreation.

Extend monitoring to cover node readiness, etcd health/snapshot age, certificate expiry, PVC capacity, broker queues, Redis persistence and application freshness. Replace or adapt Compose/journald-specific collectors in this deployment path.

Update `README.md`, inventory/platform READMEs, `docs/database-modes.md`, `docs/dns.md`, `docs/secrets.md` and add `docs/k3s-deployment.md` and `docs/k3s-recovery.md`. Document local prerequisites and exact deployment/rollback commands after the new entry points exist.

## Deployment inputs to supply later

The plan can be implemented with placeholders. A real deployment needs the selected cloud/account/region, application and API DNS names, ACME email, administrator CIDRs, SSH identity, native registry names and publishing/pulling identities, and existing secret references. Default to health-checked cloud load balancers and managed PostgreSQL; choose direct-node endpoints only when their availability tradeoff is acceptable. Nodes without public IPs require an existing local-to-cloud private route.

Before replacing an existing deployment, inventory its live data and take backups. Provision the new cluster alongside it, migrate/verify state, stop duplicate producers, switch DNS, and retire old VMs only after successful verification. Replacing the current JSON and immediately applying it could otherwise destroy the old workload hosts before the new application is ready.

---

# Review findings

Added after a read of the plan against the current code on `k3s-pavlo`. Each
item names the file that contradicts or constrains the plan. Severity is about
whether the plan as written would fail, not about how hard the fix is.

## Blockers: the plan as written will not apply

### R1. The Cloudflare DNS module breaks in k3s mode

[`modules/cloudflare/dns/main.tf`](infrastructure/terraform/modules/cloudflare/dns/main.tf)
is wired to the UI **VM**, not to an ingress endpoint, in four separate ways:

- `local.ui_vm_keys` filters `vm.role == "ui"`. With every node on
  `role: "kubernetes"` the list is empty and `one()` on an empty list raises an
  error, so the module fails before its preconditions can produce a readable
  message.
- `local.hostname` reads `vms[ui].public_endpoint.hostname`. Section 1 moves
  that value to `ingress.hostname`, so the lookup must be rewritten.
- `type = "A"` is hardcoded, and a precondition requires `local.ip_address` to
  match an IPv4 literal.
- The module publishes exactly **one** record. The plan introduces a second
  hostname (`kubernetes.api_endpoint`) that also needs to resolve.

The IPv4 assumption is the subtle one. Under `endpoint_mode:
"cloud_load_balancer"` it holds for GCP (anycast/regional static IP) and Azure
(Standard LB static IP), and for a single-AZ AWS NLB with an attached EIP. It
does **not** hold for an AWS ALB, which exposes only a DNS name, and a 3-AZ AWS
NLB exposes one EIP per zone — three addresses, which the single-record design
cannot express either way.

**Action:** make the record set data-driven (a map of name → type → target)
rather than one `A` record, and decide per provider whether the LB target is an
address or a CNAME. Add this to section 2 item 6 as an explicit deliverable;
right now section 2 only says DNS is provisioned in Terraform.

### R2. The synthetics canary will alarm continuously on ACME staging

The proposed JSON sets `"acme_environment": "staging"` as the starting value,
and section 5 item 3 correctly says to validate staging before switching. But
the existing monitoring validates certificate trust:

- [`modules/gcp/monitoring/uptime.tf:10-11`](infrastructure/terraform/modules/gcp/monitoring/uptime.tf#L10-L11)
  sets `use_ssl = true` **and** `validate_ssl = true`.
- AWS uses a real browser canary (`syn-nodejs-puppeteer-*` per the schema's
  `monitoring.synthetics.runtime_version`), which also rejects untrusted chains.

Let's Encrypt's staging CA is not publicly trusted, so both probes fail for the
entire staging window, and
[`modules/aws/monitoring/alarms.tf:38`](infrastructure/terraform/modules/aws/monitoring/alarms.tf#L38)
turns that into a firing alarm.

**Action:** section 5 needs a step that either keeps `monitoring.synthetics.enabled`
false until production issuance succeeds, or adds an explicit
"staging tolerates untrusted TLS" switch. Note the ordering dependency in
section 9 step 3 as well.

### R3. Three-AZ spread is not expressible in `region_map`

Section 1 bullet 2 and section 2 call for distributing nodes across three
availability zones with matching subnets. `region_map` in the example configs
carries exactly **one** zone per cloud:

```
eu-central → aws: availability_zone "eu-central-1a"
             gcp: zone "europe-central2-a"
             azure: availability_zone "1"
```

The plan never mentions `region_map`, so this requirement has no
implementation path. Reaching three zones means changing that map from a scalar
zone to an ordered list, then threading zone selection through all three VM
modules and the disk/LB resources that inherit zone from the VM.

**Action:** add `region_map` restructuring to the section 2 item 1 list of
things to update, or downgrade the 3-AZ goal to "single zone initially, zones
as a follow-up" and say so explicitly. Do not leave it stated as a requirement
with no owner.

### R4. The network block has no per-AZ subnets, and one subnet becomes orphaned

`network` is currently just:

```json
{ "management_subnet_cidr": "10.0.0.0/24",
  "workload_subnet_cidr": "10.0.1.0/24",
  "ui_public_ports": [80, 443] }
```

Two consequences the plan does not address. Three AZs need three subnet CIDRs,
not one `workload_subnet_cidr`. And with the bastion removed,
`management_subnet_cidr` has no occupant — it should either be deleted from the
k3s branch or explicitly documented as reserved, not silently left behind.

One thing that is **already fine:** `ui_public_ports` already includes 80, so
the HTTP-01 solver needs no new firewall opening. Section 2 item 4 can note
this is satisfied rather than listed as work.

## Schema and example-config mismatches

The plan says the JSON fragment is "not a complete file accepted by today's
schema", which covers these in general. They are listed because each one is a
decision, not just a missing field.

### R5. `tags` is the wrong key — reuse `network_tags`

`$defs/vm` has `additionalProperties: false`, so `tags` is rejected outright.
More importantly, `network_tags` already exists and already drives firewall and
routing rules in all three cloud modules. Introducing a parallel `tags` key
that means almost the same thing invites the two drifting apart.

Use `network_tags: ["control-plane", "worker"]` and delete the `tags` concept.
That also removes the need for section 1 bullet 3's normalization step, since
`network_tags` is already in provider-safe form. If literal `control plane`
with a space must be preserved for a human-facing reason, state that reason —
otherwise it is pure cost.

Also missing from the fragment and currently required by `$defs/vm`:
`network_tags` and `secret_mappings`. The latter is worth an explicit decision:
section 8 moves secret resolution to the operator's machine, so per-VM
`secret_mappings` may become an empty object rather than disappearing.

### R6. `disk_type: "ssd"` resolves to `io2` on AWS

From `disk_type_map`: `ssd` → `pd-ssd` (GCP), `io2` (AWS), `Premium_LRS`
(Azure). `io2` is provisioned-IOPS storage with a separate per-IOPS charge and
a minimum provisioning floor — a surprising bill for a 60 GiB etcd volume, and
not what "SSD-backed storage" in section 4 needs.

`balanced` maps to `gp3` on AWS, which is already SSD and is the normal choice
for etcd. Change the example to `"disk_type": "balanced"`, or add a new
map entry if genuinely high IOPS is wanted — but then justify it.

### R7. `kubernetes.admin_allowed_cidrs` duplicates existing per-VM `allowed_cidrs`

`$defs/vm` already has `allowed_cidrs` (and `ssh_port`). A new cluster-level
`admin_allowed_cidrs` means two places can restrict SSH to the same node.
Either reuse the per-VM field, or state that the cluster-level one replaces it
in k3s mode and have the schema reject the per-VM key there.

### R8. `size: "kubernetes"` names a size after a workload

`size` is a free-form key into `size_map`, so this needs no schema change —
worth correcting in section 1 bullet 1, which implies schema work. But the
naming breaks the map's one dimension: every other key (`micro`, `small`,
`medium`, `large`) describes machine capacity, so a `kubernetes` key cannot be
reused by anything else and tells a reader nothing about size.

`large` already resolves to 2 vCPU / 8 GiB on AWS (`t3.large`) and GCP
(`e2-standard-2`) — exactly the plan's target. Prefer `"size": "large"` over a
new entry, and see R9 on whether 8 GiB is the right target at all.

## R9. Cost is the plan's largest unstated change

Every VM in both example configs is `micro`, deliberately. This plan replaces
four `micro` VMs with three 2 vCPU / 8 GiB nodes plus two load balancers, and
never states the resulting cost. Rough `eu-central-1` monthly figures:

| Item | Today | Planned |
| --- | --- | --- |
| Compute | 4 × `t3.micro` ≈ $30 | 3 × `t3.large` ≈ $180 |
| Disks | 4 × 10 GiB gp3 ≈ $3 | 3 × 60 GiB `io2` ≈ $42 (≈ $15 on gp3) |
| Load balancers | none | 2 × NLB ≈ $35+ |
| NAT (if nodes go private) | none | ≈ $32 + egress |
| **Infra subtotal** | **≈ $33** | **≈ $260–290** |

Managed PostgreSQL is unchanged and excluded from both columns. That is roughly
a **9× increase**, in a repo that ships budget alerts.

Two things follow. First, this belongs in the plan as an explicit,
signed-off-on number — section 1 bullet 1 currently says only "validate actual
provider sizing", which reads like a footnote rather than a 9× decision.

Second, 8 GiB per node looks over-specced for the actual workload: three small
Python services, RabbitMQ capped at 768 MB and Redis capped at 128 MB
(`rabbitmq.memory_mb`, `redis.maxmemory_mb`). A k3s server with bundled Traefik
and ServiceLB disabled (section 3 item 6 already disables both) idles well
under 1 GiB. Starting at `medium` (2 vCPU / 4 GiB, ≈ $30/node) puts compute at
≈ $90 instead of $180, with a documented instruction to measure and resize.
Also add a note on AWS inter-AZ transfer: etcd raft traffic is continuous, so a
3-AZ spread bills for it forever.

## Gaps worth closing

### R10. Azure credentials are required for every plan

Azure shares the single Terraform root, so `terraform plan` needs Azure
credentials even for an AWS-only deployment. Section 9 step 1 asks for
"three-node Terraform plans for each supported cloud" as if each were
independent. Note the shared-root constraint so nobody budgets for an
AWS-only validation run.

### R11. The existing RabbitMQ certificate mechanism has no stated fate

`rabbitmq.certificate_days: 365` means TLS material is generated today by the
VM path. Section 5's closing paragraph introduces a cert-manager CA issuer for
broker TLS, but never says whether `certificate_days` is retired, retained for
the Compose path only, or reinterpreted as the cert-manager Certificate
duration. Pick one; a config key that silently stops having an effect is worse
than removing it.

### R12. Container memory settings need an explicit mapping

`redis.memory_mb` / `redis.maxmemory_mb` and `rabbitmq.memory_mb` are currently
Compose-level limits. Section 6 says to preserve memory limits but not that
these keys become Kubernetes requests/limits, which is the one place a
translation bug would show up as an OOMKill loop under load. Name the mapping.

### R13. Staggering etcd snapshots

`snapshot_schedule_cron: "0 */6 * * *"` runs on all three servers at the same
instant, so all three take the I/O and off-node upload hit together — on nodes
that are also running every workload. Offset the schedule per node.

### R14. No break-glass path once the bastion is gone

Today one bastion holds the only public SSH surface. Afterwards all three nodes
have public IPs with SSH and 6443 exposed, restricted only by
`admin_allowed_cidrs`. If the operator's address changes — residential IP
rotation, travel, a CI runner — the cluster becomes unreachable for both SSH
and `kubectl`, with no jump host left to fix it from. Section 2 item 4 should
name a recovery path: provider serial/session access, a documented CIDR-update
apply that does not need cluster access, or a retained minimal bastion.

### R15. Two deployment paths, no deprecation plan

`deployment_target: "k3s"` keeps the Compose path alive, which is the right
call for a safe migration. But sections 1–9 then require every future change to
land twice, and section 9's test matrix covers both. State whether Compose is
permanently supported or is removed after the migration in section 9 step 6 —
otherwise the maintenance cost is silently doubled.

### R16. Laptop-only Helm leaves no CI deployment path

Section 5 deliberately runs Helm from the operator's machine. That is
defensible, but it means no CI deployment, no drift detection, and a cluster
whose live state cannot be reconciled against Git. Section 9 asks CI to run
`helm lint` and template checks, which catches syntax but not drift. Either
accept this in writing as a known limitation, or add a `helm diff` step to the
runbook so an operator can see drift before applying.

### R17. `docs/dns.md` needs its reasoning rewritten, not just updated

Section 9 lists `docs/dns.md` among files to update. The stronger point: that
document's central argument — why the record must never be proxied — rests on
TLS-ALPN-01 being answered by the origin on :443. Switching to HTTP-01 changes
that argument, and the constraint is currently encoded as
`cloudflare.proxied` with `"const": false` in
[`project-config.schema.json`](infrastructure/terraform/project-config.schema.json)
whose description names TLS-ALPN-01 explicitly. Re-derive the constraint for
HTTP-01 before copying the old wording forward — under HTTP-01 the solver
answers on :80, so the reasoning is not the same. See R18: that constraint is
weaker than it looks.

### R18. Schema validation is not enforced anywhere automatic

This is a pre-existing defect, but the plan leans on the schema heavily enough
that it becomes a plan problem.

`cloudflare.proxied` is constrained to `"const": false` in the JSON schema, and
[`docs/dns.md`](docs/dns.md) states that "Terraform therefore refuses `proxied:
true` with an explanatory error". Terraform does no such thing:

- [`modules/cloudflare/dns/variables.tf:15`](infrastructure/terraform/modules/cloudflare/dns/variables.tf#L15)
  declares `proxied = optional(bool, false)` with **no `validation` block**, and
  there is no `check` block or precondition on it anywhere in the tree.
- [`modules/cloudflare/dns/main.tf:34`](infrastructure/terraform/modules/cloudflare/dns/main.tf#L34)
  tells the reader to "see the `proxied` validation in variables.tf" — a file
  that contains no validation. The comment misdirects.
- The schema is only ever applied by a **manual** command documented in
  [`infrastructure/ansible/oilscope/platform/README.md:10`](infrastructure/ansible/oilscope/platform/README.md#L10)
  (`uvx check-jsonschema ...`). It is not in `.pre-commit-config.yaml` and not
  in `.github/workflows/pr-validation.yml`.

So `proxied: true` reaches `terraform apply` intact if nobody runs the manual
check, which is exactly the "one-word config change silently breaks certificate
renewal 60 days later" outcome `docs/dns.md` claims is prevented.

Why this matters for the plan: section 9 adds "focused tests for
schema/topology rejection" covering exactly three nodes, both tags per VM, CIDR
overlap, endpoint-mode validity and address-combination validity. Every one of
those is a *schema* constraint, so every one of them is unenforced at apply time
under the current setup. A config that declares two nodes, or overlapping pod
and service CIDRs, would be rejected by a test nobody runs and accepted by
Terraform.

**Action:** add schema validation to `pr-validation.yml` and to
`.pre-commit-config.yaml` as a prerequisite in section 9 step 1, before relying
on schema constraints for topology safety. Where a constraint must hold at
apply time regardless of config provenance, also express it as a Terraform
`variable` `validation` or a `precondition`. Separately, fix the misleading
comment at `main.tf:34` and the overstated claim in `docs/dns.md`.

## Things the plan already gets right

Recorded so a later reader does not re-litigate them:

- Sequential server joins over the **private** bootstrap address (section 3
  item 4) correctly avoids the chicken-and-egg of joining through a load
  balancer that is not yet healthy.
- Disabling bundled Traefik and ServiceLB (section 3 item 6) is necessary given
  Terraform owns the LBs; leaving ServiceLB on would fight it.
- Refusing to use the application PostgreSQL as the Kubernetes datastore, and
  refusing Helm-deployed etcd (section 4), are both correct.
- Noting that three RabbitMQ replicas do not make non-replicated queues
  resilient (section 6) is the kind of thing usually discovered in an incident.
- `k3s-1` / `k3s-2` / `k3s-3` satisfy the existing `vms` `propertyNames`
  pattern `^[a-z][a-z0-9-]*[a-z0-9]$`, so VM naming needs no schema change.
