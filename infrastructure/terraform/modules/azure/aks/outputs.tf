output "managed_kubernetes" {
  value = local.enabled ? {
    cloud          = "azure"
    name           = azurerm_kubernetes_cluster.main[0].name
    region         = azurerm_kubernetes_cluster.main[0].location
    zone           = null
    resource_group = azurerm_kubernetes_cluster.main[0].resource_group_name
    project        = null
  } : null
}
