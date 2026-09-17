output "public_ips" {
  description = "Public IP addresses keyed by VM name."
  value = merge(
    module.gcp_workloads.public_ips,
    module.aws_workloads.public_ips,
    module.gcp_bastion.public_ips,
    module.aws_bastion.public_ips,
  )
}

output "managed_database" {
  description = "Non-secret managed PostgreSQL connection metadata."
  value = local.config.database.mode == "managed" ? {
    cloud           = local.config.default_cloud
    host            = local.config.default_cloud == "aws" ? one(module.aws_managed_database).hostname : null
    connection_name = local.config.default_cloud == "gcp" ? one(module.gcp_managed_database).connection_name : null
  } : null
}
