# Azure alerting module

Decides who hears when something breaks: an action group that mails
`observability.alert_email`, metric and log alert rules, a health alert, and
the monthly budget.

## Resources

| Resource | Fires when |
| --- | --- |
| `<prefix>-alerts` | Action group every rule notifies |
| `<vm>-cpu`, `-disk-write`, `-network-in`, `-health` | A platform metric crosses its threshold on that VM - one rule per VM and metric, because some metrics (`Network In Total`) refuse a rule over several VMs |
| `<prefix>-vm-health` | Resource health reports a VM unavailable or degraded - including stopped and deallocated VMs, which report no metric at all |
| `<prefix>-memory` | Memory in use, from `Perf`, exceeds the threshold |
| `<prefix>-container-died` | `docker-events` logged an exit with a non-zero code; the container name becomes a dimension, so the notification names it |
| `<prefix>-http-5xx` | A ui, history or fetcher VM logged a line with `status` ≥ 500 |
| `<prefix>-monthly` | Spend in the resource group exceeds `budget_usd` |

## Compared with the other clouds

| | GCP | AWS | Azure |
| --- | --- | --- | --- |
| Rules per metric | one, VMs selected by label | one per instance | one per VM |
| A VM that reports nothing | absent series alerts | missing data is breaching | resource health alert |
| Log-based alerts | log match condition | metric filter + alarm per container | KQL query with dimensions |
| Budget | billing account, filtered to the project | the account | the resource group |

Each log rule runs as its own system-assigned identity, granted
`Log Analytics Reader` on the workspace. Without one, Azure checks the workspace with the credentials
of whoever creates the rule, and that check fails about half the time with
"insufficient access", even for the subscription owner.

The log rules skip query validation, so creating them in the same apply as the
workspace does not depend on what the new workspace can already answer.

## License

GPL-2.0-or-later
