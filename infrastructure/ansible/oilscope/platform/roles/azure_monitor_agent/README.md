# Azure Monitor Agent role

Installs or updates the Azure Monitor Agent extension on every Azure VM by
calling the Azure control plane from the Ansible controller. Authentication
uses the active Azure CLI session. The extension is configured with the VM's
Terraform-created user-assigned managed identity.

Installing the agent does not by itself select data to collect. An Azure Data
Collection Rule and its VM association must exist before logs or guest metrics
are sent to a Log Analytics workspace or Azure Monitor Metrics.

Required inventory variables:

- `azure_resource_group`;
- `azure_identity_resource_id`.

## License

GPL-2.0-or-later
