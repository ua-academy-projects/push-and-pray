resource "azurerm_application_security_group" "role" {
  for_each = local.enabled ? toset(local.roles) : toset([])

  name                = "${local.resource_prefix}-${each.value}-asg"
  resource_group_name = azurerm_resource_group.main[0].name
  location            = azurerm_resource_group.main[0].location
  tags                = local.common_tags
}

resource "azurerm_network_security_group" "role" {
  for_each = local.enabled ? toset(local.roles) : toset([])

  name                = "${local.resource_prefix}-${each.value}-nsg"
  resource_group_name = azurerm_resource_group.main[0].name
  location            = azurerm_resource_group.main[0].location
  tags                = local.common_tags
}

locals {
  security_rules = merge(
    {
      for name, vm in local.azure_vms : "bastion-ssh" => {
        role         = "bastion"
        priority     = 100
        description  = "SSH from the configured operator networks"
        ports        = [tostring(vm.ssh_port)]
        source_cidrs = vm.allowed_cidrs
      } if name == "bastion"
    },
    {
      "ui-web" = {
        role         = "ui"
        priority     = 110
        description  = "Public HTTP and HTTPS"
        ports        = local.ui_public_ports
        source_cidrs = ["Internet"]
      }
      "history-api" = {
        role         = "history"
        priority     = 110
        description  = "History API from the UI"
        ports        = [tostring(var.config.service_ports.history_api)]
        source_roles = ["ui"]
      }
      "history-rabbitmq" = {
        role         = "history"
        priority     = 120
        description  = "RabbitMQ TLS from Fetcher and History"
        ports        = [tostring(var.config.rabbitmq.port)]
        source_roles = ["fetcher", "history"]
      }
      "database-postgresql" = {
        role         = "database"
        priority     = 110
        description  = "PostgreSQL from Fetcher and History"
        ports        = [tostring(var.config.service_ports.postgresql)]
        source_roles = ["fetcher", "history"]
      }
    },
    {
      for role in ["database", "history", "fetcher", "ui"] : "${role}-ssh" => {
        role         = role
        priority     = 100
        description  = "SSH from the bastion"
        ports        = ["22"]
        source_roles = ["bastion"]
      }
    },
    {
      for role in local.roles : "${role}-deny-vnet" => {
        role         = role
        priority     = 4000
        description  = "Deny the traffic Azure's default VNet rule would otherwise allow"
        access       = "Deny"
        protocol     = "*"
        ports        = ["*"]
        source_cidrs = ["VirtualNetwork"]
      }
    },
  )
}

resource "azurerm_network_security_rule" "role" {
  for_each = { for name, rule in local.security_rules : name => rule if local.enabled }

  name                        = each.key
  description                 = each.value.description
  resource_group_name         = azurerm_resource_group.main[0].name
  network_security_group_name = azurerm_network_security_group.role[each.value.role].name

  priority                   = each.value.priority
  direction                  = "Inbound"
  access                     = try(each.value.access, "Allow")
  protocol                   = try(each.value.protocol, "Tcp")
  source_port_range          = "*"
  destination_port_range     = contains(each.value.ports, "*") ? "*" : null
  destination_port_ranges    = contains(each.value.ports, "*") ? null : each.value.ports
  destination_address_prefix = "*"

  source_address_prefix   = try(length(each.value.source_cidrs), 0) == 1 ? each.value.source_cidrs[0] : null
  source_address_prefixes = try(length(each.value.source_cidrs), 0) > 1 ? each.value.source_cidrs : null
  source_application_security_group_ids = try([
    for role in each.value.source_roles : azurerm_application_security_group.role[role].id
  ], null)
}
