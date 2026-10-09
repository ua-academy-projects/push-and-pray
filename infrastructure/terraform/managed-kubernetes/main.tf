locals {
  project_config = jsondecode(file(var.project_config_path))
  config = merge(local.project_config, {
    kubernetes = merge(try(local.project_config.kubernetes, {}), {
      node_size  = try(local.project_config.kubernetes.node_size, "medium")
      node_count = try(local.project_config.kubernetes.node_count, 3)
    })
  })
  name     = "${local.config.name_prefix}-${local.config.environment}-aks"
  location = local.config.locations[local.config.default_location].azure.region
  labels   = merge(local.config.common_labels, { environment = local.config.environment })
}

resource "azurerm_resource_group" "managed_kubernetes" {
  name     = "${local.name}-rg"
  location = local.location
  tags     = local.labels

  lifecycle {
    precondition {
      condition     = local.config.default_cloud == "azure"
      error_message = "This isolated deployment root supports the configured Azure cloud only."
    }

    precondition {
      condition     = try(local.project_config.kubernetes.mode, "self_managed") == "managed"
      error_message = "The isolated managed-kubernetes state requires kubernetes.mode=managed; refusing a cross-mode apply."
    }
  }
}

resource "azurerm_virtual_network" "managed_kubernetes" {
  name                = "${local.name}-vnet"
  location            = local.location
  resource_group_name = azurerm_resource_group.managed_kubernetes.name
  address_space       = [var.vnet_cidr]
  tags                = local.labels
}

resource "azurerm_subnet" "nodes" {
  name                            = "nodes"
  resource_group_name             = azurerm_resource_group.managed_kubernetes.name
  virtual_network_name            = azurerm_virtual_network.managed_kubernetes.name
  address_prefixes                = [var.node_subnet_cidr]
  default_outbound_access_enabled = false
}

data "azurerm_virtual_network" "k3s" {
  name                = "${local.config.name_prefix}-${local.config.environment}-vnet"
  resource_group_name = "${local.config.name_prefix}-${local.config.environment}-rg"
}

resource "azurerm_virtual_network_peering" "k3s_to_managed" {
  name                         = "${local.name}-from-k3s"
  resource_group_name          = data.azurerm_virtual_network.k3s.resource_group_name
  virtual_network_name         = data.azurerm_virtual_network.k3s.name
  remote_virtual_network_id    = azurerm_virtual_network.managed_kubernetes.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "managed_to_k3s" {
  name                         = "${local.config.name_prefix}-${local.config.environment}-from-aks"
  resource_group_name          = azurerm_resource_group.managed_kubernetes.name
  virtual_network_name         = azurerm_virtual_network.managed_kubernetes.name
  remote_virtual_network_id    = data.azurerm_virtual_network.k3s.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

module "azure_kubernetes" {
  source = "../modules/azure/kubernetes"

  config              = local.config
  resource_group_name = azurerm_resource_group.managed_kubernetes.name
  subnet_id           = azurerm_subnet.nodes.id
}
