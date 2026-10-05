locals {
  ingress_rules = {
    for name, vm in local.vms : name => concat(
      vm.role == "bastion" ? [
        { name = "bastion-ssh", ports = distinct(concat([tostring(vm.ssh_port)], var.config.network.enable_bastion_ssh_bootstrap ? ["22"] : [])), sources = vm.allowed_cidrs }
        ] : [
        { name = "workload-ssh", ports = ["22"], sources = [for peer in values(local.vms) : peer.internal_ip if peer.location == vm.location && peer.role == "bastion"] }
      ],
      [for rule in [
        { name = "k3s-api", ports = ["6443"], sources = [for peer in values(local.vms) : peer.internal_ip if peer.location == vm.location && peer.role != "bastion"] },
        { name = "k3s-etcd", ports = ["2379", "2380"], sources = [for peer in values(local.vms) : peer.internal_ip if peer.location == vm.location && peer.role == "k3s_server"] }
      ] : rule if vm.role == "k3s_server"],
      vm.role == "k3s_server" && var.config.database_mode == "postgres_extensions" ? [
        { name = "postgresql", ports = [tostring(var.config.database.port)], sources = [for peer in values(local.vms) : peer.internal_ip if peer.location == vm.location && peer.role != "bastion"] }
      ] : [],
      vm.role == "k3s_server" ? [
        { name = "private-dashboards", ports = ["30081", "30082"], sources = [for peer in values(local.vms) : peer.internal_ip if peer.location == vm.location && peer.role == "bastion"] }
      ] : [],
      [for rule in [
        { name = "k3s-vxlan", protocol = "Udp", ports = ["8472"], sources = [for peer in values(local.vms) : peer.internal_ip if peer.location == vm.location && peer.role != "bastion"] },
        { name = "k3s-kubelet", ports = ["10250"], sources = [for peer in values(local.vms) : peer.internal_ip if peer.location == vm.location && peer.role != "bastion"] }
      ] : rule if vm.role != "bastion"],
      vm.role != "bastion" && try(vm.assign_public_ip, false) ? [
        { name = "ingress-web", ports = [for port in(try(var.config.cloudflare.enabled, false) ? [80, 443] : var.config.network.ingress_public_ports) : tostring(port)], sources = ["0.0.0.0/0"] }
      ] : [],
    )
  }
}

# NIC-level NSGs preserve role isolation even when UI and bastion share a subnet.
resource "azurerm_network_security_group" "vm" {
  for_each = local.vms

  name                = "${local.resource_prefix}-${each.key}-nsg"
  location            = local.locations[each.value.location].region
  resource_group_name = azurerm_resource_group.main[each.value.location].name
  tags                = merge(local.labels, { role = each.value.role })

  dynamic "security_rule" {
    for_each = { for index, rule in local.ingress_rules[each.key] : index => rule if length(rule.sources) > 0 }
    content {
      name                       = security_rule.value.name
      priority                   = 100 + tonumber(security_rule.key)
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = try(security_rule.value.protocol, "Tcp")
      source_port_range          = "*"
      destination_port_ranges    = security_rule.value.ports
      source_address_prefixes    = security_rule.value.sources
      destination_address_prefix = "*"
    }
  }

  # Override Azure's default AllowVNetInBound rule.
  security_rule {
    name                       = "deny-other-inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "database" {
  count = local.managed_database_enabled ? 1 : 0

  name                = "${local.resource_prefix}-postgres-nsg"
  location            = local.locations[var.config.default_location].region
  resource_group_name = azurerm_resource_group.main[var.config.default_location].name
  tags                = local.labels

  security_rule {
    name                       = "postgresql"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = tostring(var.config.database.port)
    source_address_prefixes    = concat(local.database_client_ips, [local.cloud_network.database_subnet_cidrs[0]], [for vm in values(local.vms) : vm.internal_ip if vm.location == var.config.default_location && vm.role == "bastion"])
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "deny-other-inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "database" {
  count = local.managed_database_enabled ? 1 : 0

  subnet_id                 = azurerm_subnet.database[0].id
  network_security_group_id = azurerm_network_security_group.database[0].id
}
