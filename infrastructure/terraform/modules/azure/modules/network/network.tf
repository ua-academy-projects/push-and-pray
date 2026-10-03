resource "azurerm_virtual_network" "main" {
  name                = "${var.resource_prefix}-vnet"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = [var.profile.network_cidr]

  tags = var.tags
}

# Every subnet is private: new subnets have no default outbound access any
# more, and it is switched off explicitly so an older API default cannot turn
# it back on. A VM reaches the internet through its own public address or,
# from the workload subnet, through NAT.
resource "azurerm_subnet" "management" {
  name                 = "${var.resource_prefix}-management"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.profile.subnets.management]

  default_outbound_access_enabled = false
}

resource "azurerm_subnet" "workload" {
  name                 = "${var.resource_prefix}-workload"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.profile.subnets.workload]

  default_outbound_access_enabled = false
}

# Holds the private endpoint in front of the managed database and nothing
# else. A private endpoint ignores the NSG unless the subnet says otherwise,
# which would leave the database open to the whole network.
resource "azurerm_subnet" "database" {
  count = var.enable_database_subnet ? 1 : 0

  name                 = "${var.resource_prefix}-database"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.profile.subnets.database[0]]

  default_outbound_access_enabled   = false
  private_endpoint_network_policies = "NetworkSecurityGroupEnabled"
}
