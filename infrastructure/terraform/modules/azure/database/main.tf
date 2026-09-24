locals {
  enabled          = var.config.database_mode == "managed" && var.config.default_cloud == "azure"
  resource_prefix  = "${var.config.name_prefix}-${var.config.environment}"
  labels           = merge(var.config.common_labels, { environment = var.config.environment })
  storage_sizes_mb = [32768, 65536, 131072, 262144, 524288, 1048576, 2097152, 4194304, 8388608, 16777216, 33553408]
}

data "azurerm_client_config" "current" {
  count = local.enabled ? 1 : 0
}

resource "azurerm_postgresql_flexible_server" "postgres" {
  count = local.enabled ? 1 : 0

  name                  = "${substr(local.resource_prefix, 0, 40)}-postgres-${substr(sha256(data.azurerm_client_config.current[0].subscription_id), 0, 8)}"
  resource_group_name   = var.resource_group_name
  location              = var.config.locations[var.config.default_location].azure.region
  version               = var.config.database.postgres_version
  sku_name              = var.config.provider_mappings.database_sizes[var.config.database.size].azure.sku_name
  storage_mb            = min([for size in local.storage_sizes_mb : size if size >= var.config.database.storage_gb * 1024]...)
  auto_grow_enabled     = true
  backup_retention_days = var.config.environment == "prod" ? 14 : 7

  delegated_subnet_id               = var.delegated_subnet_id
  private_dns_zone_id               = var.private_dns_zone_id
  public_network_access_enabled     = false
  administrator_login               = var.config.database.admin_user
  administrator_password_wo         = var.administrator_password
  administrator_password_wo_version = var.administrator_password_version
  tags                              = local.labels

  lifecycle {
    # Keep the availability zone assigned by Azure.
    ignore_changes = [zone]

    precondition {
      condition = alltrue([
        for vm in values(var.config.vms) :
        try(vm.cloud, var.config.default_cloud) == "azure" && try(vm.location, var.config.default_location) == var.config.default_location
        if vm.role != "bastion"
      ])
      error_message = "Azure managed mode requires workload VMs in Azure at default_location for private database and service connectivity."
    }
  }
}

resource "azurerm_postgresql_flexible_server_database" "application" {
  count = local.enabled ? 1 : 0

  name      = var.config.database.name
  server_id = azurerm_postgresql_flexible_server.postgres[0].id
  charset   = "UTF8"
  collation = "en_US.utf8"
}
