# GCP monitoring module

Lets every VM identity write metrics, defines which metrics matter, and draws
them on one dashboard. The metric table is the module's real product: the
alerting module builds one policy per entry from it and never names a metric
itself.

## Resources

| Resource | Purpose |
| --- | --- |
| `google_project_iam_member` | `roles/monitoring.metricWriter` for each identity |
| `google_monitoring_dashboard` | One chart per watched metric, every VM as a line, the threshold drawn across |

## Metrics

| Entry | Metric | Source | Default threshold |
| --- | --- | --- | --- |
| `cpu` | `compute.googleapis.com/instance/cpu/utilization` | GCE | 0.75 |
| `memory` | `agent.googleapis.com/memory/bytes_used`, state `used` | Ops Agent | 1.5 GB |
| `disk_write` | `compute.googleapis.com/instance/disk/write_ops_count` as a rate | GCE | 1000 ops/s |
| `network_in` | `compute.googleapis.com/instance/network/received_bytes_count` as a rate | GCE | 1 Mbit/s |
| `uptime` | `compute.googleapis.com/instance/uptime` summed per minute | GCE | none - the series stopping is the alert |

Every filter selects VMs by the `application` and `environment` labels
Terraform puts on them, so neither the dashboard nor a policy lists an
instance and a new VM is covered the moment it exists.

## Inputs

| Name | Description |
| --- | --- |
| `project_id` | Project whose IAM and dashboard are managed |
| `resource_prefix` | Prefix for the dashboard name |
| `identities` | IAM member string per VM name |
| `labels` | The common labels; `application` and `environment` are read |
| `thresholds` | Optional overrides: `cpu_utilization`, `memory_used_gb`, `disk_write_ops_per_second`, `network_received_mbit_per_second` |

## Outputs

| Name | Description |
| --- | --- |
| `metrics` | The table above, resolved: title, filter, aligner and threshold per entry |
| `dashboard_id` | Resource name of the dashboard |

## Usage

```hcl
module "monitoring" {
  source = "./modules/monitoring"
  count  = local.is_active ? 1 : 0

  project_id      = local.profile.project_id
  resource_prefix = local.resource_prefix
  identities      = local.identities
  labels          = local.common_labels
  thresholds      = try(var.config.observability.thresholds, {})
}
```

## License

GPL-2.0-or-later
