output "public_ips" {
  description = "Public IP addresses keyed by VM name."
  value = merge(
    module.gcp_workloads.public_ips,
    module.aws_workloads.public_ips,
    module.gcp_bastion.public_ips,
    module.aws_bastion.public_ips,
    module.azure_workloads.public_ips,
    module.azure_bastion.public_ips,
    module.gcp_k3s_ingress.public_ips,
    local.config.deployment_mode == "k3s" && try(local.config.kubernetes.mode, "self_managed") == "managed" ? {
      ingress = local.config.default_cloud == "gcp" ? one(module.gcp_managed_kubernetes).ingress.address : (
        local.config.default_cloud == "aws" ? one(module.aws_managed_kubernetes).ingress.address : one(module.azure_managed_kubernetes).ingress.address
      )
    } : {},
  )
}

output "managed_kubernetes" {
  description = "Managed Kubernetes cluster connection metadata."
  value = local.config.deployment_mode == "k3s" && try(local.config.kubernetes.mode, "self_managed") == "managed" ? (
    local.config.default_cloud == "gcp" ? one(module.gcp_managed_kubernetes).cluster : (
      local.config.default_cloud == "aws" ? one(module.aws_managed_kubernetes).cluster : one(module.azure_managed_kubernetes).cluster
    )
  ) : null
}

output "managed_database" {
  description = "Non-secret managed PostgreSQL connection metadata."
  value = local.config.database.mode == "managed" ? {
    cloud = local.config.default_cloud
    host = local.config.default_cloud == "aws" ? one(module.aws_managed_database).hostname : (
      local.config.default_cloud == "azure" ? one(module.azure_managed_database).hostname : null
    )
    connection_name = local.config.default_cloud == "gcp" ? one(module.gcp_managed_database).connection_name : null
  } : null
}
