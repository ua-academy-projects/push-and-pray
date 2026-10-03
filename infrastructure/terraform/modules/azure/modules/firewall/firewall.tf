resource "azurerm_application_security_group" "scope" {
  for_each = toset(local.scopes)

  name                = "${var.resource_prefix}-${each.value}"
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

resource "azurerm_network_security_rule" "workload_ssh" {
  name                        = "allow-workload-ssh"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.main.name
  priority                    = local.priorities.workload_ssh
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"

  source_application_security_group_ids = [azurerm_application_security_group.scope["bastion"].id]
  source_port_range                     = "*"
  destination_application_security_group_ids = [
    for scope in local.workload_scopes : azurerm_application_security_group.scope[scope].id
  ]
  destination_port_range = "22"
}

# The UI is public by design; Traefik terminates TLS here.
resource "azurerm_network_security_rule" "ui_web" {
  name                        = "allow-ui-web"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.main.name
  priority                    = local.priorities.ui_web
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"

  source_address_prefix                      = "Internet"
  source_port_range                          = "*"
  destination_application_security_group_ids = [azurerm_application_security_group.scope["ui"].id]
  destination_port_ranges                    = local.ui_public_ports
}

resource "azurerm_network_security_rule" "history_api" {
  name                        = "allow-history-api"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.main.name
  priority                    = local.priorities.history_api
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"

  source_application_security_group_ids      = [azurerm_application_security_group.scope["ui"].id]
  source_port_range                          = "*"
  destination_application_security_group_ids = [azurerm_application_security_group.scope["history"].id]
  destination_port_range                     = tostring(var.config.service_ports.history_api)
}

# What the infra VM serves depends on where the database runs. Self-hosted:
# PostgreSQL. Managed: the RabbitMQ broker and the Redis cache that take over
# the queue and the sessions. The clients are the same three workloads either
# way; the rule for the managed database itself comes from the database
# module.
resource "azurerm_network_security_rule" "postgresql" {
  count = var.database_managed ? 0 : 1

  name                        = "allow-postgresql"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.main.name
  priority                    = local.priorities.postgresql
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"

  source_application_security_group_ids = [
    for scope in local.infra_client_scopes : azurerm_application_security_group.scope[scope].id
  ]
  source_port_range                          = "*"
  destination_application_security_group_ids = [azurerm_application_security_group.scope["infra"].id]
  destination_port_range                     = tostring(var.config.service_ports.postgresql)
}

resource "azurerm_network_security_rule" "amqp" {
  count = var.database_managed ? 1 : 0

  name                        = "allow-amqp"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.main.name
  priority                    = local.priorities.amqp
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"

  source_application_security_group_ids = [
    for scope in local.infra_client_scopes : azurerm_application_security_group.scope[scope].id
  ]
  source_port_range                          = "*"
  destination_application_security_group_ids = [azurerm_application_security_group.scope["infra"].id]
  destination_port_range                     = tostring(var.config.service_ports.amqp)
}

resource "azurerm_network_security_rule" "redis" {
  count = var.database_managed ? 1 : 0

  name                        = "allow-redis"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.main.name
  priority                    = local.priorities.redis
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"

  source_application_security_group_ids = [
    for scope in local.infra_client_scopes : azurerm_application_security_group.scope[scope].id
  ]
  source_port_range                          = "*"
  destination_application_security_group_ids = [azurerm_application_security_group.scope["infra"].id]
  destination_port_range                     = tostring(var.config.service_ports.redis)
}

# GCP and AWS deny traffic between instances unless a rule allows it; Azure
# allows everything inside the virtual network by default. This restores the
# same contract. The load balancer probe rule Azure adds sits above it and
# stays in force.
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
