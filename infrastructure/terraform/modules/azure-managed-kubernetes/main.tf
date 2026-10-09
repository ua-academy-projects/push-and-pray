resource "azurerm_user_assigned_identity" "cluster" {
  name                = "${local.resource_prefix}-aks"
  location            = var.network.region
  resource_group_name = var.resource_group_name
  tags                = local.tags
}

resource "azurerm_role_assignment" "network" {
  scope                = var.network.private_subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.cluster.principal_id
}

resource "azurerm_public_ip" "ingress" {
  name                = "${local.resource_prefix}-kubernetes-ingress"
  location            = var.network.region
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = local.ingress_zones
  tags                = local.tags
}

resource "azurerm_role_assignment" "ingress" {
  scope                = azurerm_public_ip.ingress.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.cluster.principal_id
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = "${local.resource_prefix}-kubernetes"
  location            = var.network.region
  resource_group_name = var.resource_group_name
  dns_prefix          = "${local.resource_prefix}-kubernetes"
  kubernetes_version  = local.cluster.version
  sku_tier            = local.sku_tier

  role_based_access_control_enabled = true
  local_account_disabled            = false
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true

  node_provisioning_profile {
    mode = "Manual"
  }

  api_server_access_profile {
    authorized_ip_ranges = distinct(concat(
      var.config.bastion.allowed_cidrs,
      ["${var.network.nat_public_ip}/32"],
    ))
  }

  default_node_pool {
    name                 = "application"
    node_count           = local.cluster.node_count
    vm_size              = var.config.machine_types[local.cluster.machine_type].azure
    vnet_subnet_id       = var.network.private_subnet_id
    os_disk_size_gb      = local.cluster.disk_size_gb
    os_disk_type         = "Managed"
    zones                = local.node_zones
    auto_scaling_enabled = false
    node_labels          = { "oilscope.io/role" = "agent" }

    upgrade_settings {
      max_surge = "10%"
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.cluster.id]
  }

  oms_agent {
    log_analytics_workspace_id      = var.log_analytics_workspace_id
    msi_auth_for_monitoring_enabled = true
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "azure"
    pod_cidr            = var.config.k3s.cluster_cidr
    service_cidr        = var.config.k3s.service_cidr
    dns_service_ip      = var.config.k3s.cluster_dns
    load_balancer_sku   = "standard"
    outbound_type       = "userAssignedNATGateway"
  }

  tags = local.tags

  depends_on = [
    azurerm_role_assignment.ingress,
    azurerm_role_assignment.network,
  ]
}
