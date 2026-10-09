locals {
  secret_version_managers = try(local.profile.secret_version_managers, [])

  secret_ids = module.selection.secret_ids

  # The vault exists only where there is something to keep in it - on a cloud
  # that runs a k3s_server node.
  holds_secrets = length(local.secret_ids) > 0

  # Only k3s_server nodcd ..es read secrets. Ansible resolves them there and hands
  # them on in memory: the join token to the agents, the Tailscale key to the
  # bastions, the rest into Kubernetes Secrets.
  server_nodes = [for name, node in local.nodes : name if node.role == "k3s_server"]

  server_secret_pairs = {
    for pair in setproduct(local.server_nodes, local.secret_ids) :
    "${pair[0]}/${pair[1]}" => {
      node_name = pair[0]
      secret_id = pair[1]
    }
  }

  secret_version_writers = {
    for pair in setproduct(local.secret_ids, local.secret_version_managers) :
    "${pair[0]}/${pair[1]}" => {
      secret_id    = pair[0]
      principal_id = pair[1]
    }
  }
}

data "azurerm_client_config" "current" {
  count = local.holds_secrets ? 1 : 0
}

# The container for every secret of the environment. GCP and AWS have no such
# thing - there a secret belongs to the project or the account directly. The
# name is global across all of Azure and stays taken while a deleted vault is
# soft-deleted, which is why it comes from the profile.
#
# Access is RBAC, not access policies, so a grant looks the same as every
# other role assignment - and can be scoped to one secret, the way GCP binds
# secretAccessor. The vault is reached over its public endpoint, as Secret
# Manager and Secrets Manager are; the VMs authenticate, they are not
# allow-listed.
#trivy:ignore:AVD-AZU-0013
resource "azurerm_key_vault" "main" {
  count = local.holds_secrets ? 1 : 0

  name                = local.profile.key_vault_name
  resource_group_name = azurerm_resource_group.main[0].name
  location            = azurerm_resource_group.main[0].location
  tenant_id           = data.azurerm_client_config.current[0].tenant_id
  sku_name            = "standard"

  rbac_authorization_enabled = true

  # The shortest retention Azure allows. Purge protection stays off, so an
  # environment that is torn down can take the same name back straight away.
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  tags = local.common_tags
}

resource "azurerm_role_assignment" "operator" {
  count = local.holds_secrets ? 1 : 0

  scope                = azurerm_key_vault.main[0].id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current[0].object_id
}

resource "time_sleep" "operator_propagation" {
  count = local.holds_secrets ? 1 : 0

  create_duration = "60s"

  triggers = {
    assignment = azurerm_role_assignment.operator[0].id
  }
}

resource "azurerm_key_vault_secret" "this" {
  for_each = toset(local.secret_ids)

  name         = each.value
  key_vault_id = azurerm_key_vault.main[0].id

  value_wo         = "placeholder"
  value_wo_version = 1
  content_type     = "oilscope-placeholder"

  tags = local.common_tags

  # Every upload adds a version of its own, and the attributes Terraform reads
  # back are the latest version's. Reconciling them would write a new version
  # over the real value, so after creation they are left alone.
  lifecycle {
    ignore_changes = [content_type, expiration_date, not_before_date, tags]
  }

  depends_on = [time_sleep.operator_propagation]
}

resource "azurerm_role_assignment" "server_access" {
  for_each = local.server_secret_pairs

  scope                = azurerm_key_vault_secret.this[each.value.secret_id].resource_versionless_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.identity[each.value.node_name].principal_id
  principal_type       = "ServicePrincipal"
}

# The counterpart of roles/secretmanager.secretVersionAdder: setSecret without
# getSecret, so a version can be written but never read back. Azure has no
# built-in role that narrow.
resource "azurerm_role_definition" "version_adder" {
  count = local.holds_secrets && length(local.secret_version_managers) > 0 ? 1 : 0

  name        = "${local.resource_prefix}-secret-version-adder"
  scope       = azurerm_key_vault.main[0].id
  description = "Adds a version to a secret without being able to read one"

  permissions {
    data_actions = ["Microsoft.KeyVault/vaults/secrets/setSecret/action"]
  }

  assignable_scopes = [azurerm_key_vault.main[0].id]
}

resource "azurerm_role_assignment" "version_adder" {
  for_each = local.secret_version_writers

  scope              = azurerm_key_vault_secret.this[each.value.secret_id].resource_versionless_id
  role_definition_id = azurerm_role_definition.version_adder[0].role_definition_resource_id
  principal_id       = each.value.principal_id
}
