locals {
  name       = "${var.config.name_prefix}-${var.config.environment}-aks"
  location   = var.config.locations[var.config.default_location].azure.region
  node_size  = try(var.config.kubernetes.node_size, "medium")
  node_count = try(var.config.kubernetes.node_count, 3)
  labels     = merge(var.config.common_labels, { environment = var.config.environment })
}

resource "azurerm_user_assigned_identity" "cluster" {
  name                = "${local.name}-identity"
  location            = local.location
  resource_group_name = var.resource_group_name
  tags                = local.labels
}

resource "azurerm_role_assignment" "network" {
  scope                = var.subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.cluster.principal_id
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = local.name
  location            = local.location
  resource_group_name = var.resource_group_name
  dns_prefix          = local.name
  tags                = local.labels

  default_node_pool {
    name           = "system"
    node_count     = local.node_count
    vm_size        = var.config.provider_mappings.instance_types[local.node_size].azure.vm_size
    vnet_subnet_id = var.subnet_id
    tags           = local.labels

    upgrade_settings {
      max_surge                     = "10%"
      drain_timeout_in_minutes      = 0
      node_soak_duration_in_minutes = 0
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.cluster.id]
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
  }

  storage_profile { disk_driver_enabled = true }

  depends_on = [azurerm_role_assignment.network]
}
