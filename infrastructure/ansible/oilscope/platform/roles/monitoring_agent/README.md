# Monitoring agent role

Installs and configures the cloud-native monitoring agent on an existing
OilScope workload VM: the CloudWatch Agent on AWS, the Ops Agent on GCP. It
runs on the workload host itself, as part of a deployment play, not on
`localhost`.

Terraform (`infrastructure/terraform/modules/aws/monitoring`,
`modules/gcp/monitoring`) grants each VM's existing identity the permissions
the agent needs and renders that VM's exact agent configuration - CloudWatch
Agent JSON on AWS, Ops Agent YAML on GCP - as a Terraform output, keyed by
VM name. This role is the install side used at deploy time: it reads that
rendered configuration and writes it to disk unchanged, then starts/restarts
the agent service. It never re-derives thresholds, intervals, or log paths
itself, and it never opens a cloud API connection to fetch this data -
Terraform has already validated and rendered it.

## What it guarantees

- Only the current host's own entry in `agent_configurations` is ever used -
  matched by `oilscope_vm_key`, never by `oilscope_role` (two VMs can share a
  role) and never by re-parsing `inventory_hostname`.
- A VM with no entry in `agent_configurations` (monitoring not enabled for
  it, or - on the UI VM - only some of `agent_metrics_enabled`/
  `logs_enabled` set) is a valid, expected state: the role finishes as a
  clean no-op for that host rather than failing.
- An `oilscope_cloud` that isn't `gcp`/`aws` fails the play immediately.
- The configuration content written to disk is exactly the string Terraform
  rendered - never re-encoded, re-templated, or reformatted here.
- On AWS, the CloudWatch Agent `.deb` is never installed without a verified
  GPG signature - `gpgv` against a keyring built from the downloaded public
  key, and the key's own fingerprint is checked against the value AWS
  publishes out-of-band before it's trusted for anything. A mismatch on
  either check fails the play; nothing is installed.
- On GCP, the Ops Agent is installed once via Google's own installer script
  (idempotency is via `package_facts`, not by re-running the script) and
  pinned to a major version (`monitoring_agent_gcp_version`).
- Applying a changed configuration always ends with a health check - `ctl -a
  status` on AWS, `systemctl is-active` on GCP - retried for transient
  IAM/API-propagation delays, and the play fails if the agent never reports
  healthy. A restart notification always goes through the mechanism that
  actually reloads config (`amazon-cloudwatch-agent-ctl -a fetch-config` on
  AWS, since the unit only ever reads the `.toml` that command regenerates;
  a plain `systemctl restart` on GCP, which reads `config.yaml` directly).

## Requirements

The target VM must already have the agent's IAM/service-account permissions
attached - this is what `infrastructure/terraform/modules/aws/monitoring`
and `modules/gcp/monitoring` grant automatically to the VM's existing role/
service account. This role does not grant any cloud permissions itself.

## Required variables

- `monitoring_agent_config_path`: path to the JSON file produced by
  `terraform output -json aws_monitoring` or
  `terraform output -json gcp_monitoring` - whichever matches this run's
  cloud (a run only ever targets one cloud; see `preflight.yml`).
- `oilscope_vm_key`, `oilscope_cloud`: normally inherited automatically from
  the dynamic inventory (`oilscope_gcp` / `oilscope_aws`); only need setting
  by hand outside of it, such as in a role test against a static inventory.

## Optional variables

- `monitoring_agent_work_dir` (default `/opt/oilscope/monitoring`): scratch
  and staging directory shared by both clouds' task files - a VM only ever
  runs one cloud's agent, so there's no collision.
- AWS: `monitoring_agent_aws_package_base_url`, `monitoring_agent_aws_gpg_key_url`,
  `monitoring_agent_aws_gpg_fingerprint`, `monitoring_agent_aws_ctl`. AWS
  publishes no version-pinned download URL (only "latest" per
  architecture); dpkg's own version check keeps re-runs idempotent instead
  of a docker_engine-style pin.
- GCP: `monitoring_agent_gcp_install_script_url`, `monitoring_agent_gcp_version`
  (default `2.*.*`), `monitoring_agent_gcp_config_path`,
  `monitoring_agent_gcp_service`.

## Output

Nothing is exposed as a role fact for later tasks to consume - the agent
configuration is written to disk and the agent service is (re)started;
that's the entire effect of this role.

## License

GPL-2.0-or-later
