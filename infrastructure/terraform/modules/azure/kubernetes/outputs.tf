output "cluster" {
  value = {
    cloud               = "azure"
    name                = azurerm_kubernetes_cluster.main.name
    region              = azurerm_kubernetes_cluster.main.location
    resource_group_name = azurerm_kubernetes_cluster.main.resource_group_name
  }
}
