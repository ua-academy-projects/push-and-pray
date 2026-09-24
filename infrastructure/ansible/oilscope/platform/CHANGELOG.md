# Changelog

All notable changes to the `oilscope.platform` collection.

This project follows [semantic versioning](https://semver.org/).

## Unreleased

- Added Azure as a third supported cloud. `oilscope_azure` wraps
  `azure.azcollection.azure_rm`, scoping discovery to
  `clouds.azure.resource_group_name` and combining location and the
  application/environment tags into one ANDed include filter, because that
  plugin ORs the entries of that list. `resolve_secrets`, `secret_versions`,
  `database_migrate` and `monitoring_agent` gained an `azure.yml` and an
  explicit three-cloud dispatch.

- Azure's monitoring agent is installed by Terraform, not by this collection.
  `monitoring_agent` verifies the Azure Monitor Agent extension and the data
  collection configuration it fetched, and prepares the log files those rules
  read; it never writes a competing rule. Disabling monitoring on Azure is a
  Terraform operation, so the role reports a leftover extension rather than
  stopping a service the next apply would restart.

- `database_connection` can now assemble one CA bundle from several published
  roots, for a provider that publishes no single bundle. Azure's Flexible
  Server chains to DigiCert Global Root G2 or Microsoft RSA Root Certificate
  Authority 2017, one served as PEM and one as DER; both are handled without
  installing anything on the VM. AWS and GCP keep their single-URL path.

- Fixed `secret_versions` reporting success for a cloud it has no
  implementation for. It built a catalog, matched no dispatch condition,
  uploaded nothing and exited 0; it now rejects the cloud by name before any
  value is read.

- Fixed `monitoring_agent`'s disable path treating every non-AWS cloud as GCP,
  and `database_migrate`'s secret read falling through to an undefined GCP
  register for any cloud without an explicit branch — which, under `no_log`,
  produced a diagnostic naming the wrong provider.

- Unified monitoring and database connection inputs under the required
  `terraform_outputs_path` argument. Monitoring selects the current cloud's
  output from the complete Terraform outputs file. Removed self-referencing
  monitoring role parameters from workload playbooks.

- Added the managed migration playbook/role before History, controller-side
  administrator-secret retrieval, per-VM runtime logins and table grants,
  deployment-time access verification, and password URL encoding.

- Added `database_connection` for inventory/managed PostgreSQL selection,
  verified cloud TLS, public CA mounting/refresh, and common service connection
  environment. Cloud mode requires refreshed `terraform_outputs_path` JSON.
  Fetcher and History use the role before Compose rendering; UI no longer
  does, since its session store moved to Redis. Removed Fetcher's legacy
  database-host/user/name defaults.

- Added `rabbitmq` (self-signed TLS, vhost/exchange/queue/retry/dead-letter
  topology, admin-password reconciliation) and `redis` (TLS-free, single
  co-located UI host, AOF persistence) roles, plus `broker_connection` to
  resolve RabbitMQ's inventory host, install its CA bundle, and build each
  consuming service's connection environment. Both run in every database
  mode on both clouds and are deployed via `rabbitmq.yml` (imported from
  `deploy_workloads.yml`) and directly from `ui.yml`, respectively. PGMQ
  publishing/consumption and PostgreSQL-backed UI sessions were replaced
  with a durable-outbox RabbitMQ publisher/consumer and native-TTL Redis
  sessions in application code; see the root README's Architecture section.

## 0.2.0

- Added the `monitoring_agent` role: installs and configures the
  CloudWatch Agent (AWS) / Ops Agent (GCP) on existing workload VMs from
  the per-VM configuration Terraform renders
  (`aws_monitoring`/`gcp_monitoring` outputs' `agent_configurations`). A VM
  with no entry in that output is a clean no-op. Wired into
  `database.yml`, `history.yml`, `fetcher.yml`, and `ui.yml` via a new
  `monitoring_agent_config_path` extra-var.
- `edge_proxy` and `compose_project`'s proxy Compose template now emit
  Traefik's JSON access log (and rotate it via `logrotate`), gated by
  `monitoring.logs_enabled` in the project configuration; absent for any
  configuration written before this setting existed.

## 0.1.0

- Initial collection scaffold: `galaxy.yml`, `meta/runtime.yml` and the
  directory layout. No roles or plugins yet.
