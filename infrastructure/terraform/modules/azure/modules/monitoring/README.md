# Azure monitoring module

Holds the table of watched metrics and draws the dashboard. Alerting reads the
table, so thresholds live in one place.

## Metrics

| Key | Platform metric | Aggregation | Alert when |
| --- | --- | --- | --- |
| `cpu` | `Percentage CPU` | average | above `cpu_utilization` × 100 |
| `disk_write` | `OS Disk Write Operations/Sec` | average | above `disk_write_ops_per_second` |
| `network_in` | `Network In Total` | total over the window | above `network_received_mbit_per_second`, scaled to the window |
| `health` | `VmAvailabilityMetric` | average | below 1 |

These are platform metrics: Azure collects them for every VM without an agent.
Memory is not among them, because the platform does not measure memory in
use; the agent sends it to the workspace, and alerting queries it there
(`memory_threshold_mb`).

Every alert looks at a five-minute window (`window_minutes`), and totals are
scaled to it here and nowhere else - the counterpart of the per-second rates
on GCP and the 60-second sums on AWS.

## Dashboard

`<prefix>-hosts`: one chart per metric, one line per VM. Platform metrics are
addressed by resource ID, so like CloudWatch and unlike GCP there is no label
to select the VMs by; the list comes from `instances`.

## License

GPL-2.0-or-later
