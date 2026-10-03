# A throwaway administrator password. The server insists on one when it is
# created, and it goes through a write-only argument, so it never lands in
# the plan or the state; managed_database_credentials replaces it with the
# password the workloads read from Key Vault.
ephemeral "random_password" "bootstrap" {
  length      = 32
  special     = false
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
}

# The server has no address in the network and no public access: like Cloud
# SQL behind Private Service Connect, it is reached only through the private
# endpoint below. The administrator is the application role, as on AWS; its
# login is fixed at creation and cannot be renamed.
resource "azurerm_postgresql_flexible_server" "main" {
  name                = local.name
  resource_group_name = var.resource_group_name
  location            = var.location
  zone                = var.zone
  version             = var.settings.engine_version
  sku_name            = var.sku_name

  storage_mb        = local.storage_mb
  auto_grow_enabled = true

  backup_retention_days        = local.backup_retention_days
  geo_redundant_backup_enabled = false

  public_network_access_enabled = false

  administrator_login               = var.settings.username
  administrator_password_wo         = ephemeral.random_password.bootstrap.result
  administrator_password_wo_version = 1
  authentication {
    password_auth_enabled         = true
    active_directory_auth_enabled = false
  }

  tags = var.tags
}

resource "azurerm_postgresql_flexible_server_configuration" "extensions" {
  name      = "azure.extensions"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = join(",", local.extensions)
}

# A static parameter: the server restarts to apply it. After the extension
# list, because the server takes one configuration change at a time.
resource "azurerm_postgresql_flexible_server_configuration" "preload" {
  name      = "shared_preload_libraries"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = join(",", local.preload_libraries)

  depends_on = [azurerm_postgresql_flexible_server_configuration.extensions]
}

resource "azurerm_postgresql_flexible_server_database" "application" {
  name      = var.settings.name
  server_id = azurerm_postgresql_flexible_server.main.id
  charset   = "UTF8"
  collation = "en_US.utf8"

  depends_on = [azurerm_postgresql_flexible_server_configuration.preload]
}

# The Azure counterpart of the GCP address and forwarding rule: a network
# interface in the database subnet that forwards to the server. Its address,
# not the server's name, is what the workloads see as DATABASE_HOST - no
# private DNS zone, the same trade-off as on GCP.
resource "azurerm_private_endpoint" "main" {
  name                          = "${local.name}-endpoint"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  subnet_id                     = var.subnet_id
  custom_network_interface_name = "${local.name}-endpoint-nic"

  private_service_connection {
    name                           = "${local.name}-endpoint"
    private_connection_resource_id = azurerm_postgresql_flexible_server.main.id
    subresource_names              = ["postgresqlServer"]
    is_manual_connection           = false
  }

  tags = var.tags

  # The server takes one operation at a time and answers ServerIsBusy to the
  # next; connecting the endpoint while a parameter is applied - the static one
  # restarts it - fails the apply. So the endpoint waits for all of them.
  depends_on = [azurerm_postgresql_flexible_server_database.application]
}

# The counterpart of the RDS security group: the endpoint admits the port from
# the three workloads and the infra VM, which runs the migrations. It lives in
# the network's one security group, between the allow rules and the deny.
resource "azurerm_network_security_rule" "clients" {
  name                        = "allow-database"
  resource_group_name         = var.resource_group_name
  network_security_group_name = var.network_security_group_name
  priority                    = var.rule_priority
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"

  source_application_security_group_ids = values(var.client_application_security_group_ids)
  source_port_range                     = "*"
  destination_address_prefix            = var.subnet_cidr
  destination_port_range                = tostring(var.port)
}

# Azure has no deletion protection flag on the server; a lock refuses the
# delete instead, and has to be removed before the server can go.
resource "azurerm_management_lock" "server" {
  count = var.settings.deletion_protection ? 1 : 0

  name       = "${local.name}-lock"
  scope      = azurerm_postgresql_flexible_server.main.id
  lock_level = "CanNotDelete"
  notes      = "database.deletion_protection is on in the project configuration"
}
