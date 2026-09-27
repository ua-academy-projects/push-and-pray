resource "azurerm_network_security_group" "vm" {
  for_each = local.vms_by_role

  name                = "${var.resource_prefix}-${each.key}-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = merge(var.tags, { role = each.key })
}

resource "azurerm_network_security_rule" "bastion_ssh" {
  for_each = contains(keys(local.vms_by_role), "bastion") ? toset(var.bastion_allowed_cidrs) : toset([])

  name                        = "ssh-${replace(replace(each.value, "/", "-"), ".", "-")}"
  priority                    = 100 + index(var.bastion_allowed_cidrs, each.value)
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = tostring(var.bastion_ssh_port)
  source_address_prefix       = each.value
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.vm["bastion"].name
}

resource "azurerm_network_security_rule" "bastion_bootstrap_ssh" {
  for_each = contains(keys(local.vms_by_role), "bastion") && var.enable_bastion_ssh_bootstrap && var.bastion_ssh_port != 22 ? toset(var.bastion_allowed_cidrs) : toset([])

  name                        = "bootstrap-ssh-${replace(replace(each.value, "/", "-"), ".", "-")}"
  priority                    = 200 + index(var.bastion_allowed_cidrs, each.value)
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = each.value
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.vm["bastion"].name
}

resource "azurerm_network_security_rule" "ui_public" {
  for_each = contains(keys(local.vms_by_role), "ui") ? toset([for port in var.ui_public_ports : tostring(port)]) : toset([])

  name                        = "public-${each.value}"
  priority                    = 100 + index([for port in var.ui_public_ports : tostring(port)], each.value)
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = each.value
  source_address_prefix       = "Internet"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.vm["ui"].name
}

resource "azurerm_network_security_rule" "bastion_to_workloads" {
  for_each = {
    for name, vm in local.workload_vms : name => vm
    if local.bastion_ip != null
  }

  name                        = "ssh-from-bastion"
  priority                    = 300
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "${local.bastion_ip}/32"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.vm[each.value.role].name
}

resource "azurerm_network_security_rule" "ui_to_history" {
  count = contains(keys(local.vms_by_role), "ui") && contains(keys(local.vms_by_role), "history") ? 1 : 0

  name                        = "history-api-from-ui"
  priority                    = 400
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = tostring(var.history_api_port)
  source_address_prefix       = "${local.vms_by_role.ui.internal_ip}/32"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.vm["history"].name
}

resource "azurerm_network_security_rule" "self_managed_postgres" {
  for_each = local.self_managed_database_sources

  name                        = "postgres-from-${each.key}"
  priority                    = 500 + index(sort(keys(local.self_managed_database_sources)), each.key)
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = tostring(var.postgresql_port)
  source_address_prefix       = "${each.value}/32"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.vm["database"].name
}

resource "azurerm_network_security_rule" "rabbitmq" {
  for_each = local.rabbitmq_sources

  name                        = "rabbitmq-from-${each.key}"
  priority                    = 600 + index(sort(keys(local.rabbitmq_sources)), each.key)
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = tostring(var.rabbitmq_port)
  source_address_prefix       = "${each.value}/32"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.vm[local.infrastructure_nsg_role].name
}

resource "azurerm_network_security_rule" "redis" {
  for_each = local.redis_sources

  name                        = "redis-from-${each.key}"
  priority                    = 700
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = tostring(var.redis_port)
  source_address_prefix       = "${each.value}/32"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.vm[local.infrastructure_nsg_role].name
}

resource "azurerm_network_security_group" "managed_database" {
  count = var.managed_database_enabled ? 1 : 0

  name                = "${var.resource_prefix}-managed-postgres-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_network_security_rule" "managed_database" {
  count = var.managed_database_enabled && contains(keys(local.vms_by_role), "history") ? 1 : 0

  name                        = "postgres-from-history"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = tostring(var.postgresql_port)
  source_address_prefix       = "${local.vms_by_role.history.internal_ip}/32"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.managed_database[0].name
}
