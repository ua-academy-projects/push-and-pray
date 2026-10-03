# Azure logging module

Creates the Log Analytics workspace, the data collection rule that tells every
agent what to send there, and the Azure Monitor Agent on every VM.

## Resources

| Resource | Purpose |
| --- | --- |
| `<prefix>-logs` | The workspace; retention 30 to 730 days |
| `<prefix>-hosts` | Data collection rule: syslog, all facilities and levels, and the `Used Memory MBytes` counter |
| `AzureMonitorLinuxAgent` | The agent, as an extension of every VM, the bastion included |
| `<prefix>-<vm>-hosts` | The association of each VM with the rule |

## How it differs from the other clouds

- **The agent is installed here, not by Ansible.** Microsoft ships it only as a
  VM extension. The `observability_agent` role's Azure branch makes journald
  forward to rsyslog - the agent reads syslog, not the journal - and checks the
  agent is running.
- **What to collect is a resource in the cloud**, not a file on the host.
- **No writer role.** On GCP and AWS every identity gets a log and a metric
  writer role; here the association of the VM with the rule is what lets the
  agent send.
- **The agent authenticates as the VM's user-assigned identity.** Left to
  choose, it would ask Azure to add a system-assigned one, and a second
  identity makes the metadata service ambiguous for `resolve_secrets`.

## What arrives

A journal entry reaches the `Syslog` table with the message in `SyslogMessage`,
its `SYSLOG_IDENTIFIER` in `ProcessName` and the VM name in `Computer`. The
journal's own fields do not travel through rsyslog, so a container's lines are
tagged with its ID rather than its name; the alerts tell services apart by
host. Memory in use arrives in `Perf`.

## License

GPL-2.0-or-later
