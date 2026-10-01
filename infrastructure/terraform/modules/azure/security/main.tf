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

# Packets from a workload node retain their remote-cloud destination while
# entering the bastion NIC. They therefore do not match Azure's default
# AllowVNetInBound rule, whose destination must also be VirtualNetwork.
resource "azurerm_network_security_rule" "bastion_k3s_workload_transit" {
  for_each = contains(keys(local.vms_by_role), "bastion") ? toset(["6443", "10250", "2379", "2380"]) : toset([])

  name                        = "k3s-transit-${each.value}"
  priority                    = 250 + index(["6443", "10250", "2379", "2380"], each.value)
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = each.value
  source_address_prefix       = var.k3s_node_cidr
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.vm["bastion"].name
}

resource "azurerm_network_security_rule" "bastion_flannel_workload_transit" {
  count = contains(keys(local.vms_by_role), "bastion") ? 1 : 0

  name                        = "flannel-transit-8472"
  priority                    = 260
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Udp"
  source_port_range           = "*"
  destination_port_range      = "8472"
  source_address_prefix       = var.k3s_node_cidr
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.vm["bastion"].name
}

resource "azurerm_network_security_rule" "bastion_remote_k3s_transit" {
  for_each = contains(keys(local.vms_by_role), "bastion") ? {
    for pair in setproduct(toset(var.tailscale_transit_remote_cidrs), toset(["6443", "10250", "2379", "2380"])) :
    "${pair[0]}-${pair[1]}" => {
      cidr = pair[0]
      port = pair[1]
    }
  } : {}

  name                        = "remote-k3s-${replace(replace(each.value.cidr, "/", "-"), ".", "-")}-${each.value.port}"
  priority                    = 270 + index(sort([for pair in setproduct(toset(var.tailscale_transit_remote_cidrs), toset(["6443", "10250", "2379", "2380"])) : "${pair[0]}-${pair[1]}"]), each.key)
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = each.value.port
  source_address_prefix       = each.value.cidr
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.vm["bastion"].name
}

resource "azurerm_network_security_rule" "bastion_remote_flannel_transit" {
  for_each = contains(keys(local.vms_by_role), "bastion") ? toset(var.tailscale_transit_remote_cidrs) : toset([])

  name                        = "remote-flannel-${replace(replace(each.value, "/", "-"), ".", "-")}-8472"
  priority                    = 280 + index(sort(var.tailscale_transit_remote_cidrs), each.value)
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Udp"
  source_port_range           = "*"
  destination_port_range      = "8472"
  source_address_prefix       = each.value
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.vm["bastion"].name
}

resource "azurerm_network_security_rule" "k3s_remote_control_plane" {
  for_each = contains(keys(local.vms_by_role), "k3s_server") ? {
    for pair in setproduct(toset(var.k3s_remote_node_cidrs), toset(["6443", "10250", "2379", "2380"])) :
    "${pair[0]}-${pair[1]}" => { cidr = pair[0], port = pair[1] }
  } : {}

  name                        = "remote-k3s-peer-${replace(replace(each.value.cidr, "/", "-"), ".", "-")}-${each.value.port}"
  priority                    = 800 + index(sort([for pair in setproduct(toset(var.k3s_remote_node_cidrs), toset(["6443", "10250", "2379", "2380"])) : "${pair[0]}-${pair[1]}"]), each.key)
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = each.value.port
  source_address_prefix       = each.value.cidr
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.vm["k3s_server"].name
}

resource "azurerm_network_security_rule" "k3s_remote_flannel" {
  for_each = contains(keys(local.vms_by_role), "k3s_server") ? toset(var.k3s_remote_node_cidrs) : toset([])

  name                        = "remote-k3s-flannel-${replace(replace(each.value, "/", "-"), ".", "-")}-8472"
  priority                    = 810 + index(sort(var.k3s_remote_node_cidrs), each.value)
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Udp"
  source_port_range           = "*"
  destination_port_range      = "8472"
  source_address_prefix       = each.value
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.vm["k3s_server"].name
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
