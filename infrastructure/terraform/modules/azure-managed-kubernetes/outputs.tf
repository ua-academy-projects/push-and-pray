output "cluster" {
  description = "AKS cluster connection metadata."
  value = {
    id                  = azurerm_kubernetes_cluster.this.id
    name                = azurerm_kubernetes_cluster.this.name
    location            = azurerm_kubernetes_cluster.this.location
    resource_group_name = var.resource_group_name
    endpoint            = azurerm_kubernetes_cluster.this.fqdn
  }
}

output "ingress" {
  description = "Reserved public address for the managed ingress controller."
  value = {
    address = azurerm_public_ip.ingress.ip_address
    id      = azurerm_public_ip.ingress.id
  }
}
