# Azure Monitor Agent role

This role installs the native Azure Monitor Agent VM extension on every host in
the `azure` inventory group. The extension is managed through the Azure API
from the Ansible controller and uses each VM's Terraform-managed user-assigned
identity.

Azure workload Compose definitions send container output directly to the host's
rsyslog socket with the Docker `syslog` logging driver and the `local0`
facility. The Terraform-managed data collection rule collects that facility
into Log Analytics. Bastions receive host metrics, heartbeats, and system logs
but do not run workload containers.

The role removes the obsolete `imfile` rule that attempted to read Docker's
root-owned JSON log files. It does not configure container logging itself;
that belongs to the `compose_project` role so a Compose configuration change
recreates each affected container with the correct logging driver.

Terraform owns the Log Analytics workspace, data collection rules and
associations, alert rules, availability test, and workbook. It must not also
manage the `AzureMonitorLinuxAgent` extension.
