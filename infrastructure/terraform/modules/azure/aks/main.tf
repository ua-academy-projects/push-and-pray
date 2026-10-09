resource "azurerm_kubernetes_cluster" "main" {
  count = local.enabled ? 1 : 0

  name                = local.cluster_name
  resource_group_name = var.resource_group_name
  location            = var.location
  dns_prefix          = local.resource_prefix
  sku_tier            = "Free"

  local_account_disabled  = false
  node_os_upgrade_channel = "Unmanaged"

  default_node_pool {
    name           = "system"
    vm_size        = var.config.machine_types[var.config.kubernetes.node_machine_type].azure
    node_count     = var.config.kubernetes.node_count
    vnet_subnet_id = var.subnet_id
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    pod_cidr            = "10.244.0.0/16"
    service_cidr        = "10.245.0.0/16"
    dns_service_ip      = "10.245.0.10"
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
  }

  api_server_access_profile {
    authorized_ip_ranges = local.authorized_ip_ranges
  }

  tags = merge(
    local.merged_common_tags,
    {
      Name  = local.cluster_name
      Cloud = "azure"
    }
  )
}

resource "azurerm_role_assignment" "subnet_network_contributor" {
  count = local.enabled ? 1 : 0

  scope                            = var.subnet_id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.main[0].identity[0].principal_id
  skip_service_principal_aad_check = true
}
