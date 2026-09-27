resource "azurerm_network_security_group" "vm" {
  for_each = var.vms

  name                = "${local.resource_prefix}-${each.key}-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = merge(local.common_tags, { role = each.value.role })
}

resource "azurerm_network_security_rule" "bastion_ssh" {
  for_each = local.bastion_ssh_rules

  name                        = "ssh-${each.key}"
  priority                    = each.value.priority
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = tostring(each.value.port)
  source_address_prefix       = each.value.cidr
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.vm[each.value.vm_name].name
}

resource "azurerm_network_security_rule" "bastion_bootstrap" {
  for_each = {
    for key, rule in local.bastion_ssh_rules : key => rule
    if var.enable_bastion_ssh_bootstrap && rule.port != 22
  }

  name                        = "ssh-bootstrap-${each.key}"
  priority                    = each.value.priority + 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = each.value.cidr
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.vm[each.value.vm_name].name
}

resource "azurerm_network_security_rule" "workload_ssh" {
  for_each = local.workload_ssh_targets

  name                        = "ssh-from-management"
  priority                    = 300
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefixes     = var.management_source_cidrs
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.vm[each.key].name
}

resource "azurerm_network_security_rule" "ui_web" {
  for_each = {
    for rule in flatten([
      for name, vm in local.ui_targets : [
        for port in var.config.network.ui_public_ports : {
          key     = "${name}-${port}"
          vm_name = name
          port    = port
        }
      ]
    ]) : rule.key => rule
  }

  name                        = "web-${each.value.port}"
  priority                    = 400 + each.value.port
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = tostring(each.value.port)
  source_address_prefix       = "Internet"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.vm[each.value.vm_name].name
}

resource "azurerm_network_security_rule" "history_api" {
  for_each = local.history_targets

  name                        = "history-api"
  priority                    = 600
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = tostring(var.config.service_ports.history_api)
  source_address_prefixes     = var.trusted_vnet_cidrs
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.vm[each.key].name
}

resource "azurerm_network_security_rule" "database_service" {
  for_each = local.database_targets

  name                        = var.database_mode == "managed" ? "rabbitmq" : "postgresql"
  priority                    = 700
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = tostring(var.database_mode == "managed" ? var.config.service_ports.rabbitmq : var.config.service_ports.postgresql)
  source_address_prefixes     = var.trusted_vnet_cidrs
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.vm[each.key].name
}
