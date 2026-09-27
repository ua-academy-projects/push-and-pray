locals {
  vault_name          = substr("${replace(var.resource_prefix, "-", "")}kv${substr(sha256(var.subscription_id), 0, 6)}", 0, 24)
  managed_secret_ids  = toset(nonsensitive(keys(var.secret_values)))
  external_secret_ids = setsubtract(var.secret_ids, local.managed_secret_ids)
}

resource "azurerm_key_vault" "main" {
  name                = local.vault_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = var.tenant_id
  sku_name            = "standard"

  rbac_authorization_enabled    = false
  enabled_for_disk_encryption   = false
  purge_protection_enabled      = false
  soft_delete_retention_days    = 7
  public_network_access_enabled = true
  tags                          = var.tags

  access_policy {
    tenant_id = var.tenant_id
    object_id = var.deployer_object_id

    secret_permissions = [
      "Backup",
      "Delete",
      "Get",
      "List",
      "Purge",
      "Recover",
      "Restore",
      "Set",
    ]
  }

  dynamic "access_policy" {
    for_each = {
      for name, secret_ids in var.secret_ids_by_vm : name => secret_ids
      if length(secret_ids) > 0
    }

    content {
      tenant_id          = var.tenant_id
      object_id          = var.principal_ids[access_policy.key]
      secret_permissions = ["Get", "List"]
    }
  }
}

resource "azurerm_key_vault_secret" "external" {
  for_each = local.external_secret_ids

  name         = each.value
  value        = "REPLACE_ME"
  key_vault_id = azurerm_key_vault.main.id
  tags         = var.tags

  lifecycle {
    ignore_changes = [value]

    precondition {
      condition     = can(regex("^[0-9A-Za-z-]{1,127}$", each.value))
      error_message = "Azure Key Vault secret IDs may contain only letters, digits, and hyphens."
    }
  }
}

resource "azurerm_key_vault_secret" "managed" {
  for_each = local.managed_secret_ids

  name         = each.value
  value        = var.secret_values[each.value]
  key_vault_id = azurerm_key_vault.main.id
  tags         = var.tags

  lifecycle {
    precondition {
      condition     = can(regex("^[0-9A-Za-z-]{1,127}$", each.value))
      error_message = "Azure Key Vault secret IDs may contain only letters, digits, and hyphens."
    }
  }
}
