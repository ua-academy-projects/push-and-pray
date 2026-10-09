resource "azurerm_application_security_group" "scope" {
  for_each = toset(local.scopes)

  name                = "${var.resource_prefix}-${replace(each.value, "_", "-")}"
  resource_group_name = var.resource_group_name
  location            = var.location

  tags = var.tags
}

# One security group for the whole network, attached to every subnet - the
# place GCP keeps its firewall rules too. Unlike a GCP network, it starts
# open inside: the built-in AllowVnetInBound rule admits everything from the
# virtual network, which is what deny_vnet_inbound below closes.
resource "azurerm_network_security_group" "main" {
  name                = "${var.resource_prefix}-nsg"
  resource_group_name = var.resource_group_name
  location            = var.location

  tags = var.tags
}

resource "azurerm_subnet_network_security_group_association" "main" {
  for_each = var.subnet_ids

  subnet_id                 = each.value
  network_security_group_id = azurerm_network_security_group.main.id
}

resource "azurerm_network_security_rule" "bastion_ssh" {
  name                        = "allow-bastion-ssh"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.main.name
  priority                    = local.priorities.bastion_ssh
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"

  source_address_prefixes                    = var.bastion.allowed_cidrs
  source_port_range                          = "*"
  destination_application_security_group_ids = [azurerm_application_security_group.scope["bastion"].id]
  destination_port_range                     = tostring(var.bastion.ssh_port)
}

resource "azurerm_network_security_rule" "bastion_ssh_bootstrap" {
  count = var.enable_bastion_ssh_bootstrap && var.bastion.ssh_port != 22 ? 1 : 0

  name                        = "allow-bastion-ssh-bootstrap"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.main.name
  priority                    = local.priorities.bastion_ssh_bootstrap
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"

  source_address_prefixes                    = var.bastion.allowed_cidrs
  source_port_range                          = "*"
  destination_application_security_group_ids = [azurerm_application_security_group.scope["bastion"].id]
  destination_port_range                     = "22"
}

# Direct WireGuard connections between tailnet devices. Without it Tailscale
# still works, relayed through DERP and noticeably slower.
resource "azurerm_network_security_rule" "bastion_tailscale" {
  name                        = "allow-bastion-tailscale"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.main.name
  priority                    = local.priorities.bastion_tailscale
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Udp"

  source_address_prefix                      = "Internet"
  source_port_range                          = "*"
  destination_application_security_group_ids = [azurerm_application_security_group.scope["bastion"].id]
  destination_port_range                     = tostring(var.tailscale.port)
}

# A packet a node sends to another cloud or to the tailnet is routed to the
# bastion still addressed to its real destination, so an application security
# group - which matches the interface's own address - cannot describe it. The
# rule names the destinations instead.
resource "azurerm_network_security_rule" "bastion_forwarding" {
  name                        = "allow-bastion-forwarding"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.main.name
  priority                    = local.priorities.bastion_forwarding
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"

  source_address_prefix        = var.network_cidr
  source_port_range            = "*"
  destination_address_prefixes = var.remote_cidrs
  destination_port_range       = "*"
}

# Ansible reaches the nodes over the tailnet, which arrives with a tailnet
# source address; from the bastion itself it is the fallback. A rule takes
# either groups or prefixes as its source, never both, hence two.
resource "azurerm_network_security_rule" "node_ssh_bastion" {
  name                        = "allow-node-ssh-bastion"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.main.name
  priority                    = local.priorities.node_ssh_bastion
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"

  source_application_security_group_ids = [azurerm_application_security_group.scope["bastion"].id]
  source_port_range                     = "*"
  destination_application_security_group_ids = [
    for scope in local.node_scopes : azurerm_application_security_group.scope[scope].id
  ]
  destination_port_range = "22"
}

resource "azurerm_network_security_rule" "node_ssh_tailnet" {
  name                        = "allow-node-ssh-tailnet"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.main.name
  priority                    = local.priorities.node_ssh_tailnet
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"

  source_address_prefix = var.tailscale.address_range
  source_port_range     = "*"
  destination_application_security_group_ids = [
    for scope in local.node_scopes : azurerm_application_security_group.scope[scope].id
  ]
  destination_port_range = "22"
}

resource "azurerm_network_security_rule" "cluster" {
  for_each = local.cluster_ports

  name                        = "allow-${each.key}"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.main.name
  priority                    = each.value.priority
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = title(each.value.protocol)

  source_address_prefixes = var.cluster_cidrs
  source_port_range       = "*"
  destination_application_security_group_ids = [
    for role in each.value.roles : azurerm_application_security_group.scope[role].id
  ]
  destination_port_ranges = [for port in each.value.ports : tostring(port)]
}

# Path MTU discovery needs ICMP: the tunnel between the clouds carries smaller
# packets than the networks on either side, and without "fragmentation
# needed" coming back large packets vanish silently. It also makes ping work.
resource "azurerm_network_security_rule" "cluster_icmp" {
  name                        = "allow-cluster-icmp"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.main.name
  priority                    = local.priorities.cluster_icmp
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Icmp"

  source_address_prefixes = var.cluster_cidrs
  source_port_range       = "*"
  destination_application_security_group_ids = [
    for scope in concat(local.node_scopes, ["bastion"]) : azurerm_application_security_group.scope[scope].id
  ]
  destination_port_range = "*"
}

resource "azurerm_network_security_rule" "ingress_web" {
  name                        = "allow-ingress-web"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.main.name
  priority                    = local.priorities.ingress_web
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"

  source_address_prefix                      = "Internet"
  source_port_range                          = "*"
  destination_application_security_group_ids = [azurerm_application_security_group.scope["ingress"].id]
  destination_port_ranges                    = [for port in var.cluster.ingress.public_ports : tostring(port)]
}

# GCP and AWS deny traffic between instances unless a rule allows it; Azure
# allows everything inside the virtual network by default. This restores the
# same contract; the allow rules above open what the cluster needs.
resource "azurerm_network_security_rule" "deny_vnet_inbound" {
  name                        = "deny-vnet-inbound"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.main.name
  priority                    = local.priorities.deny_vnet_inbound
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"

  source_address_prefix      = "VirtualNetwork"
  source_port_range          = "*"
  destination_address_prefix = "VirtualNetwork"
  destination_port_range     = "*"
}
