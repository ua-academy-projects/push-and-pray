# GCP Ops Agent

Installs the Google Cloud Ops Agent on existing GCP VMs. The built-in agent
configuration exports host metrics such as CPU, memory, filesystem, disk, and
network usage. On workload hosts, this role also collects Docker's JSON log
files and sends them to Cloud Logging as the `docker_json` log.

The role does not restart application containers. It restarts only the Ops
Agent when its configuration changes.

## Requirements

- Run only on members of the dynamic inventory's `gcp` group.
- The VM must have outbound HTTPS access to `dl.google.com`,
  `packages.cloud.google.com`, `logging.googleapis.com`, and
  `monitoring.googleapis.com`.
- The attached service account must have `roles/logging.logWriter` and
  `roles/monitoring.metricWriter`. The Terraform `gcp-observability` module
  grants these roles.
- Ubuntu 26.04 requires Ops Agent 2.70.0 or newer. The default installs the
  latest available release from Google's repository.

## Variables

- `gcp_ops_agent_version`: version expression passed to Google's installer;
  default `latest`. Google's Ubuntu 26.04 repository currently provides the
  `all` channel but not the major-version-only `2` channel.
- `gcp_ops_agent_collect_docker_logs`: whether to install the Docker log
  receiver. It defaults to true for hosts in the `workloads` group.
- The remaining defaults expose the installer URL, package, service, and
  configuration paths.

## Run

```bash
ansible-playbook oilscope.platform.configure_gcp_observability \
  -i infrastructure/ansible/inventory/oilscope.yml
```

The playbook is idempotent and can be run against existing VMs.

## License

GPL-2.0-or-later
