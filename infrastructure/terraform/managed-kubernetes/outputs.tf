output "managed_kubernetes" {
  description = "Non-secret AKS identity for Ansible control-host credential retrieval."
  value       = module.azure_kubernetes.cluster
}

output "kubernetes_mode" {
  value = "managed"
}
