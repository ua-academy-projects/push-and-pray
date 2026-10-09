# Azure alerting module

Decides who hears when something breaks: an action group that mails
`observability.alert_email`, metric and log alert rules, a health alert, and
the monthly budget.

What runs inside the cluster - pods restarting, services answering 5xx - is
not watched here: k3s runs containers through containerd, not Docker, so the
journal no longer names them. That belongs to Prometheus in the cluster.

## Resources

| Resource | Fires when |
| --- | --- |
| `<prefix>-alerts` | Action group every rule notifies |
| `<vm>-cpu`, `-disk-write`, `-network-in`, `-health` | A platform metric crosses its threshold on that VM - one rule per VM and metric, because some metrics (`Network In Total`) refuse a rule over several VMs |
| `<prefix>-vm-health` | Resource health reports a VM unavailable or degraded - including stopped and deallocated VMs, which report no metric at all |
| `<prefix>-memory` | Memory in use, from `Perf`, exceeds the threshold |
| `<prefix>-monthly` | Spend in the resource group exceeds `budget_usd` |

## Compared with the other clouds

| | GCP | AWS | Azure |
| --- | --- | --- | --- |
| Rules per metric | one, VMs selected by label | one per instance | one per VM |
| A VM that reports nothing | absent series alerts | missing data is breaching | resource health alert |
| Budget | billing account, filtered to the project | the account | the resource group |

The memory rule queries the workspace and runs as its own system-assigned identity, granted
`Log Analytics Reader` on the workspace. Without one, Azure checks the workspace with the credentials
of whoever creates the rule, and that check fails about half the time with
"insufficient access", even for the subscription owner.

The memory rule skips query validation, so creating it in the same apply as the
workspace does not depend on what the new workspace can already answer.

## License

GPL-2.0-or-later
