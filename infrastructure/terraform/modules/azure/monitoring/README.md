# Azure monitoring module

Log Analytics workspace, data collection rules, the Azure Monitor Agent
extension, metric and log alerts, an action group, a workbook and an
availability test — gated by the same `monitoring.*` flags AWS and GCP read.

## Terraform installs the agent

On AWS and GCP this module only *exports* an agent configuration and deployment
installs it. The Azure Monitor Agent does not work that way: it is a VM
extension whose configuration lives in cloud-side data collection rules.

So Terraform owns the extension, the rules and the associations.
`agent_configurations` is not a file to install — it names what Terraform
already created, plus the log paths deployment has to produce. Deployment
prepares those files and verifies the agent; it must not create a competing
rule.

## Custom tables

Azure has no per-VM custom metric namespace, so the collector's measurements
are ingested as logs. Three tables, created with their schemas:

| Table | Source file | Written by |
| --- | --- | --- |
| `OilscopeAccess_CL` | `/var/log/oilscope/traefik-access.log` | Traefik JSON access log, UI only, `logs_enabled` |
| `OilscopeService_CL` | `/var/log/oilscope/docker-<service>.log` | container logs, `service_logs_enabled` |
| `OilscopeMetrics_CL` | `/var/log/oilscope/application-metrics.jsonl` | the collector, `application_metrics_enabled` |

`OilscopeMetrics_CL` is the Phase 2 contract. One flat JSON object per line, per
measurement:

```json
{"Timestamp": "2026-09-22T10:00:00Z", "VMKey": "fetcher", "Role": "fetcher", "Metric": "OutboxPending", "Value": 3}
```

Nested records will not ingest — the declared stream is flat. `TimeGenerated` is
derived from `Timestamp` by the rule's transform, so the collector does not set
it.

One rule per role, not per VM: roles differ only in which files they ship.

## Retention

Log Analytics accepts **30–730** days. The shared `log_retention_days` default
of 7 is a CloudWatch value and Azure will reject it. Where the shared enum and
Azure's range overlap: 30, 60, 90, 120, 150, 180, 365, 400, 545. Set one
explicitly for an Azure deployment; 30 is the lowest.

## Alerts

| Signal | Mechanism |
| --- | --- |
| VM CPU | metric alert on the VM resource — no agent needed |
| Managed database CPU / storage / connections | metric alert on the server |
| Guest memory and disk | log alert over `InsightsMetrics` |
| HTTP 500 / 5xx | log alert over `OilscopeAccess_CL` |
| Application measurements | log alert over `OilscopeMetrics_CL`, one per VM and metric, from `monitoring-metrics.json` |
| Agent or collector stopped reporting | log alert counting rows, firing on zero |

The absence rules count rows rather than reading a value, so a metric that was
never seen does not read as a healthy zero.

## Availability test, and what it is not

`synthetics` produces an Application Insights **standard** availability test:
an HTTPS request, a status-code check, a certificate check and a text match.

It is not what the other two clouds do. AWS Synthetics runs a browser journey;
the GCP uptime check asserts a JSON path. Azure can do neither, so
`browser_enabled` stays an AWS-only setting and a text match on `ok` stands in
for GCP's `$.status`. Azure accepts 5, 10 or 15 minute intervals only — the
shared enum's 30 and 60 have no Azure equivalent.

## Dashboard

`dashboard_enabled` produces a workbook rather than a portal dashboard, so the
charts run the same KQL the alerts do and the two cannot drift. Managed database
metrics are platform metrics and are not in the workspace, so they appear in the
alerts but not in the workbook.
