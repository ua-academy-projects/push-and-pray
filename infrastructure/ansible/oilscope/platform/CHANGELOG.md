# Changelog

All notable changes to the `oilscope.platform` collection.

This project follows [semantic versioning](https://semver.org/).

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
