resource "azurerm_network_security_group" "management" {
  count = local.bastion != null ? 1 : 0

  name                = "${local.resource_prefix}-management-nsg"
  resource_group_name = var.resource_group_name
  location            = var.location

  security_rule {
    name                       = "allow-bastion-ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = local.bastion_ssh_ports
    source_address_prefixes    = local.bastion.allowed_cidrs
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "management" {
  count = local.bastion != null ? 1 : 0

  subnet_id                 = var.management_subnet_id
  network_security_group_id = azurerm_network_security_group.management[0].id
}

resource "azurerm_network_security_group" "workload" {
  count = var.has_selected_vms ? 1 : 0

  name                = "${local.resource_prefix}-workload-nsg"
  resource_group_name = var.resource_group_name
  location            = var.location
}

resource "azurerm_subnet_network_security_group_association" "workload" {
  count = var.has_selected_vms ? 1 : 0

  subnet_id                 = var.workload_subnet_id
  network_security_group_id = azurerm_network_security_group.workload[0].id
}