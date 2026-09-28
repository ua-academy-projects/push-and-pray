locals {
  resource_prefix    = "${var.config.name_prefix}-${var.config.environment}"
  subscription_short = substr(replace(var.config.cloud_settings.azure.subscription_id, "-", ""), 0, 8)
  name_stem          = trim(substr(local.resource_prefix, 0, 42), "-")
  server_name        = "${local.name_stem}-${local.subscription_short}-postgres"
  database_dns_zone  = "${local.name_stem}-${local.subscription_short}.postgres.database.azure.com"
  internal_dns_zone  = "${local.resource_prefix}.internal"

  sku_names = {
    micro  = "B_Standard_B1ms"
    small  = "B_Standard_B2s"
    medium = "B_Standard_B2ms"
  }

  tags = merge(
    {
      application = var.config.name_prefix
      environment = var.config.environment
      managed_by  = "terraform"
    },
    var.config.common_labels,
  )
}

resource "azurerm_subnet" "postgresql" {
  name                 = "${local.resource_prefix}-${var.config.default_location}-postgres"
  resource_group_name  = var.resource_group_name
  virtual_network_name = var.network.vnet_name
  address_prefixes     = [var.config.network.managed_database.azure_delegated_subnet_cidr]

  delegation {
    name = "postgresql-flexible-server"

    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_private_dns_zone" "postgresql" {
  name                = local.database_dns_zone
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgresql" {
  name                 = "${local.resource_prefix}-postgres"
  private_dns_zone_id  = azurerm_private_dns_zone.postgresql.id
  virtual_network_id   = var.network.vnet_id
  registration_enabled = false
  tags                 = local.tags
}

resource "azurerm_postgresql_flexible_server" "this" {
  name                          = local.server_name
  location                      = var.network.region
  resource_group_name           = var.resource_group_name
  version                       = var.config.database.version
  delegated_subnet_id           = azurerm_subnet.postgresql.id
  private_dns_zone_id           = azurerm_private_dns_zone.postgresql.id
  public_network_access_enabled = false

  administrator_login               = "oil_tracker"
  administrator_password_wo         = var.password
  administrator_password_wo_version = 1

  sku_name                     = local.sku_names[var.config.database.size]
  storage_mb                   = var.config.database.storage_gb * 1024
  auto_grow_enabled            = true
  backup_retention_days        = 7
  geo_redundant_backup_enabled = false
  zone                         = try(var.network.zone, null)
  tags                         = local.tags

  authentication {
    active_directory_auth_enabled = false
    password_auth_enabled         = true
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgresql]
}

resource "azurerm_management_lock" "postgresql" {
  count = var.config.environment == "dev" ? 0 : 1

  name       = "${local.resource_prefix}-postgres-delete-lock"
  scope      = azurerm_postgresql_flexible_server.this.id
  lock_level = "CanNotDelete"
  notes      = "Protect the managed PostgreSQL server outside development."
}

resource "azurerm_postgresql_flexible_server_database" "this" {
  name      = "oil_tracker"
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

resource "azurerm_private_dns_zone" "internal" {
  name                = local.internal_dns_zone
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "internal" {
  name                 = "${local.resource_prefix}-internal"
  private_dns_zone_id  = azurerm_private_dns_zone.internal.id
  virtual_network_id   = var.network.vnet_id
  registration_enabled = false
  tags                 = local.tags
}

resource "azurerm_private_dns_cname_record" "postgresql" {
  name                = "postgres"
  private_dns_zone_id = azurerm_private_dns_zone.internal.id
  ttl                 = 60
  record              = azurerm_postgresql_flexible_server.this.fqdn
  tags                = local.tags

  depends_on = [azurerm_private_dns_zone_virtual_network_link.internal]
}
