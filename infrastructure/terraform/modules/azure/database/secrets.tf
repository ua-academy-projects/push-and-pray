resource "random_password" "admin" {
  count   = local.enabled ? 1 : 0
  length  = 32
  special = false
}

resource "azurerm_key_vault_secret" "admin" {
  count = local.enabled ? 1 : 0

  name         = "${local.resource_prefix}-database-admin"
  key_vault_id = var.vault.id
  content_type = "application/json"
  tags         = local.tags

  value = jsonencode({
    username = local.admin_username
    password = random_password.admin[0].result
  })
}
