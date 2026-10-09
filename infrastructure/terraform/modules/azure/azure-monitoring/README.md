# Azure monitoring module

This module creates the Azure-native monitoring path for every selected Azure
VM:

- one Log Analytics workspace per VM region, because each regional Data
  Collection Rule requires a destination workspace in the same Azure location;
- one email action group;
- regional Linux Data Collection Rules for CPU, memory, swap, disk and syslog;
- one DCR association and one five-minute CPU alert per VM;
- one Azure Portal dashboard with a CPU chart per VM;
- an optional Application Insights HTTPS web test and availability alert.

The Azure Monitor Agent itself is installed by the Ansible
`azure_monitor_agent` role. Terraform owns the workspace, rules, associations,
dashboard and alerts. The HTTPS test expects status 200, so HTTP 500 and other
non-success responses count as failures.
