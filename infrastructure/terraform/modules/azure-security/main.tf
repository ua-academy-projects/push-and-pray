resource "azurerm_network_security_group" "tag" {
  for_each = local.functional_tags

  name                = "${local.resource_prefix}-${each.value.location}-${each.value.tag}-nsg"
  location            = each.value.region
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

resource "azurerm_network_security_rule" "bastion_ssh" {
  for_each = local.bastions

  name                        = "allow-bastion-ssh"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = tostring(each.value.ssh_port)
  source_address_prefixes     = each.value.allowed_cidrs
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.tag["${each.key}/bastion"].name
}

resource "azurerm_network_security_rule" "workload_ssh" {
  for_each = local.workload_ssh_rules

  name                        = "allow-ssh-from-bastion"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "${each.value.bastion_ip}/32"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.tag[each.key].name
}

resource "azurerm_network_security_rule" "ui_web" {
  for_each = local.ui_rules

  name                        = "allow-public-web"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = [for port in var.config.network.ui_public_ports : tostring(port)]
  source_address_prefix       = "Internet"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.tag[each.key].name
}

resource "azurerm_network_security_rule" "history_api" {
  for_each = local.history_rules

  name                        = "allow-history-api-from-ui"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = tostring(var.config.service_ports.history_api)
  source_address_prefix       = "${each.value.source_ip}/32"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.tag["${each.key}/history"].name
}

resource "azurerm_network_security_rule" "postgresql" {
  for_each = local.postgresql_rules

  name                        = "allow-postgresql-from-workloads"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = tostring(var.config.service_ports.postgresql)
  source_address_prefixes     = [for ip in each.value.source_ips : "${ip}/32"]
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.tag["${each.key}/infrastructure"].name
}
