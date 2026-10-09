output "names" {
  value = module.vm.names
}

output "internal_ips" {
  value = module.vm.internal_ips
}

output "public_ips" {
  value = module.vm.public_ips
}

output "iam_role_arns" {
  value = module.iam.iam_role_arns
}

output "iam_role_names" {
  value = module.iam.iam_role_names
}

output "managed_db_private_ip" {
  value = module.rds.endpoint
}

output "managed_kubernetes" {
  value = local.managed_kubernetes_enabled ? {
    cloud          = "aws"
    name           = module.eks.cluster_name
    region         = module.eks.region
    zone           = null
    resource_group = null
    project        = null
  } : null
}
