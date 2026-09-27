# Current OilScope architecture

This is a navigation map of the inspected working tree, not proof that a deployment succeeds. Source files and the [project-config schema](../infrastructure/terraform/project-config.schema.json) take precedence when implementation changes. See [mentor requirements](mentor-requirements.md) for constraints and [architecture decisions](architecture-decisions.md) for mode-dependent or superseded designs.

## Repository and application

- services/fetcher is the Go scheduler and OilPriceAPI client. It publishes versioned price events through PGMQ in postgres_extensions mode or RabbitMQ in managed mode.
- services/history is the Python/FastAPI consumer and PostgreSQL history API. It persists observations before acknowledging or archiving events.
- services/ui/backend is the Python/FastAPI browser gateway and session store; services/ui/frontend is the React/TypeScript interface. The browser reads persisted observations through UI, which calls History.
- database/migrations owns the PostgreSQL schema. infrastructure/docker holds image definitions and legacy/per-VM Compose definitions; infrastructure/vagrant remains a legacy development topology.

The [README](../README.md) describes the data flow. Runtime switches are implemented in [Fetcher config](../services/fetcher/internal/config/config.go), [History config](../services/history/src/history_service/config.py), and [UI backend](../services/ui/backend/src/ui_service/main.py).

## Shared configuration and Terraform

Terraform [root orchestration](../infrastructure/terraform/main.tf) reads one external, non-secret JSON configuration through [locals.tf](../infrastructure/terraform/locals.tf). The schema defines default cloud/location, environment, abstract VM and database sizes, provider mappings, networks, monitoring, Cloudflare, registry, and VMs. Per-VM cloud selection falls back to default_cloud; managed PostgreSQL is selected by database_mode plus default_cloud. The Terraform backend is GCS.

AWS, GCP, and Azure each have network, VM, database, and monitoring modules under infrastructure/terraform/modules. Provider modules resolve their own instance, image, and disk mappings. The working tree additionally contains untracked ECR, Artifact Registry, and ACR modules, selected by default_cloud, and a container_registry output. Treat these registry additions as active work, not a proven rollout.

The logical VM roles are bastion, database, history, fetcher, and ui. Root Terraform synthesizes the default bastion from shared defaults; additional bastions use VM entries. The database VM remains for PostgreSQL or managed-database migration work. VM modules support boot disk settings and optional additional disks. See [root outputs](../infrastructure/terraform/outputs.tf), the [schema](../infrastructure/terraform/project-config.schema.json), and the provider VM modules for exact selection.

## Network, SSH, and secrets

Provider/location networks use management and workload subnets with restricted role ingress. AWS uses an internet gateway and workload NAT; GCP uses Cloud NAT and Private Services Access for Cloud SQL; Azure uses a VNet, NIC security groups, and a delegated private database subnet when applicable. Managed databases have no public endpoint. There is no implemented cross-cloud or cross-location private peering. See the provider network modules and [database modes](database-modes.md).

The [dynamic inventory plugin](../infrastructure/ansible/oilscope/platform/plugins/inventory/oilscope.py) delegates live discovery to cloud inventory collections, creates role groups, supplies internal_ip and host context, and generates workload SSH ProxyCommand through a same-cloud/location bastion. It uses instance-identity host-key aliases. The bastion is public; workload SSH uses private addresses. A public UI address is optional and restricted by VM module checks.

Application secrets are declared by Ansible roles, uploaded/read through the selected cloud secret service, and kept out of project configuration and Terraform outputs. AWS RDS generates its administrator credential; Azure managed PostgreSQL accepts a sensitive, ephemeral Terraform input. See [secrets](secrets.md). Never copy secret values into documentation.

## Database modes

| Mode | PostgreSQL | Messaging | UI sessions |
| --- | --- | --- | --- |
| postgres_extensions | Container on database VM with required extensions and migrations | PGMQ in PostgreSQL | PostgreSQL with hstore, pgcrypto, and pg_cron |
| managed | Private RDS, Cloud SQL, or Azure Flexible Server in default_cloud; database VM runs migrations | RabbitMQ on History | Redis on UI |

Terraform exposes non-secret managed_database metadata for inventory. Exact provisioning and application-role logic lives in the [database role](../infrastructure/ansible/oilscope/platform/roles/database/tasks/main.yml). The mode switch is project-wide; there is no separate managed-DB provider selector. See [database modes](database-modes.md).

## Deployment paths and images

The [oilscope.platform collection](../infrastructure/ansible/oilscope/platform/README.md) contains the inventory plugin, host baseline, bastion, secret, Docker/Compose, proxy, application, and K3s roles. Its individual database, history, fetcher, and ui playbooks still implement the Compose path. Compose pulls explicit image tags from registry.repository and registry.image_tag, currently documented with GHCR authentication.

The current, modified [aggregate deploy_workloads playbook](../infrastructure/ansible/oilscope/platform/playbooks/deploy_workloads.yml) instead imports database.yml, deploy_k3s.yml, and the untracked deploy_k3s_workloads.yml. K3s installs a server on the database VM and agents on History, Fetcher, and UI. The workload role requires one host per role and an explicit OILSCOPE_IMAGE_TAG. Its Ansible-rendered templates create the oilscope namespace, ConfigMap, Kubernetes Secrets, Deployments and Services, optional RabbitMQ/Redis, and UI Traefik Ingress. The role reads the active cloud registry from Terraform output. These files are active, unverified work; no end-to-end deployment is established by their presence.

[GitHub Actions](../.github/workflows/publish-images.yaml) builds and publishes Fetcher, History, UI, and database images to GHCR. The untracked [push-k3s-images.sh](../scripts/push-k3s-images.sh) builds and pushes the three application images to the new cloud registry. The database Compose path still uses its configured image. Do not assume GHCR has been fully replaced.

## Public HTTPS and monitoring

Terraform [Cloudflare resources](../infrastructure/terraform/cloudflare.tf) can set a proxied UI A record and strict SSL. The Compose UI path uses Nginx and Certbot DNS-01; the K3s path installs cert-manager through Helm and uses Cloudflare DNS-01 to issue and renew the TLS Secret consumed by Traefik Ingress. See [Cloudflare HTTPS](cloudflare-https.md) for the Cloudflare configuration.

AWS monitoring uses CloudWatch alarms/dashboard/log groups and an agent; GCP uses Cloud Monitoring alerts/dashboard, Ops Agent, and an optional configured billing budget; Azure uses Monitor and Log Analytics workspaces, AMA, data-collection rules, and CPU/availability/filesystem alerts. See [native monitoring](native-monitoring.md) and [Azure monitoring](azure.md#monitoring-and-logging). Application-log alerts and synthetic checks are not part of the documented native monitoring scope.

## Known documentation and topology limits

- [Supported Compose deployment](supported-compose-deployment.md) still describes the aggregate playbook as Compose-only; the inspected working tree routes that entry point to K3s after database setup. Follow the actual playbook and do not silently describe either path as finalized.
- [project-config.example.json](../project-config.example.json) includes workloads on multiple clouds. Terraform multi-cloud support does not establish one reachable cross-cloud K3s cluster; K3s joins agents to the database server's private address.
- [Database modes](database-modes.md) states that Terraform rejects all mixed-cloud managed topologies. An explicit same-cloud/location guard is visible for Azure; equivalent AWS/GCP enforcement was not established in this inspection. Verify before relying on that statement.
