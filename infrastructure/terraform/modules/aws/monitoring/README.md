# AWS monitoring module

Creates workload host/application alarms, dashboards, log destinations and
optional public HTTPS/browser canaries. Root configuration excludes bastion.
Managed RDS identity comes from the database module; independent cost alerts
come from the sibling budget module.

See [the monitoring guide](../../../../../docs/monitoring.md) for configuration,
signals, thresholds, permissions, deployment, budget scopes and validation.

`agent_configurations` and `collector_configurations` are exported through root
`aws_monitoring` for Ansible. AWS-native CPU/status metrics require no agent;
guest metrics and EMF collection use CloudWatch Agent. The application collector
uses local service diagnostics without additional database/cloud credentials.

Set `synthetics.clouds=["aws"]` explicitly to run the canary without AWS VMs
(for example against a GCP-hosted UI). Browser journeys are optional. Artifacts
are private, encrypted and expire after seven days. The canary bucket deliberately
does not force-delete results on destroy; empty or retain it deliberately.

Run `terraform -chdir=infrastructure/terraform test` from repository root.
Tests live in `infrastructure/terraform/tests` and use mocked providers.
Run `node --test infrastructure/terraform/modules/aws/monitoring/canary/health.test.js`
for the HTTPS validation tests. Local checks do not prove live alert delivery.
