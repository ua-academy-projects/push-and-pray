output "bastion_public_ip" {
  description = "Bastion public IP."
  value       = try(merge(module.gcp_vm.vms, module.aws_vm.vms)["bastion"].public_ip, null)
}

output "aws_nat_gateway_public_ip" {
  description = "Public egress IP of the AWS NAT Gateway, or null when NAT is disabled."
  value       = module.aws_network.nat_public_ip
}

output "workload_vm_names" {
  description = "VM names by workload."
  value = {
    for name, workload in merge(module.gcp_vm.vms, module.aws_vm.vms) : name => workload.name
    if workload.role != "bastion"
  }
}

output "workload_roles" {
  description = "Roles by workload."
  value = {
    for name, workload in merge(module.gcp_vm.vms, module.aws_vm.vms) : name => workload.role
    if workload.role != "bastion"
  }
}

output "workload_internal_ips" {
  description = "Internal IPs by workload."
  value = {
    for name, workload in merge(module.gcp_vm.vms, module.aws_vm.vms) : name => workload.internal_ip
    if workload.role != "bastion"
  }
}

output "workload_external_ips" {
  description = "External IPs by workload."
  value = {
    for name, workload in merge(module.gcp_vm.vms, module.aws_vm.vms) : name => workload.public_ip
    if workload.role != "bastion"
  }
}

output "workload_network_tags" {
  description = "Network tags by workload."
  value = {
    for name, workload in merge(module.gcp_vm.vms, module.aws_vm.vms) : name => workload.network_tags
    if workload.role != "bastion"
  }
}

output "workload_service_account_emails" {
  description = "Service-account emails by workload."
  value = {
    for name, workload in merge(module.gcp_vm.vms, module.aws_vm.vms) : name => workload.service_account_email
    if workload.role != "bastion" && workload.service_account_email != null
  }
}

output "workload_clouds" {
  description = "Selected cloud for each workload."
  value = {
    for name, workload in merge(module.gcp_vm.vms, module.aws_vm.vms) : name => workload.cloud
    if workload.role != "bastion"
  }
}

output "secret_ids" {
  description = "GCP Secret Manager container IDs created for GCP workloads."
  value       = module.gcp_secrets.secret_ids
}

output "secret_resource_names" {
  description = "Fully qualified GCP Secret Manager resource names, by secret ID."
  value       = module.gcp_secrets.secret_resource_names
}

output "workload_secret_access" {
  description = "Secret IDs each GCP workload service account may read."
  value       = module.gcp_secrets.workload_secret_access
}

output "database_connection" {
  description = "Non-secret database connection metadata consumed by deployment automation."
  value = {
    mode       = var.database_mode
    cloud      = local.database_cloud
    host       = local.database_host
    port       = local.config.service_ports.postgresql
    name       = var.database_name
    username   = var.database_username
    sslmode    = local.database_runtime.sslmode
    identifier = local.aws_managed_database ? module.aws_rds.identifier : local.gcp_managed_database ? module.gcp_cloud_sql.instance_name : null
  }
}

output "managed_database_secret_reference" {
  description = "Secret ARN or Secret Manager ID containing managed database credentials. This reference is not the password."
  value       = local.managed_database_enabled ? local.database_secret_reference : null
}

output "queue_connection" {
  description = "Non-secret queue connection metadata."
  value = {
    backend  = local.database_runtime.queue_backend
    host     = local.database_runtime.queue_host
    port     = local.database_runtime.queue_port
    username = local.database_runtime.queue_username
    vhost    = local.database_runtime.queue_vhost
  }
}

output "ui_dns_record" {
  description = "Terraform-managed Cloudflare UI DNS record, or null when Cloudflare DNS is disabled."
  value = local.cloudflare_ui_dns_enabled ? {
    id           = cloudflare_dns_record.ui[0].id
    hostname     = cloudflare_dns_record.ui[0].name
    ipv4_address = cloudflare_dns_record.ui[0].content
    proxied      = cloudflare_dns_record.ui[0].proxied
  } : null
}
