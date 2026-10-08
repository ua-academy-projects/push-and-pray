output "bastion_public_ip" {
  description = "Bastion public IP, independent of its cloud."
  value       = lookup(merge(module.gcp.public_ips, module.aws.public_ips, module.azure.public_ips), "bastion", null)
}

output "tailscale_subnet_router_auth_key" {
  description = "Reusable tagged auth key for the three subnet-router bastions. Treat as a secret; it is stored in Terraform state."
  value       = try(tailscale_tailnet_key.subnet_router[0].key, null)
  sensitive   = true
}

output "workload_vm_names" {
  description = "VM names by workload across all configured clouds."
  value       = merge(module.gcp.workload_names, module.aws.workload_names, module.azure.workload_names)
}

output "workload_roles" {
  description = "Roles by workload across all configured clouds."
  value       = merge(module.gcp.workload_roles, module.aws.workload_roles, module.azure.workload_roles)
}

output "workload_internal_ips" {
  description = "Internal IPs by workload across all configured clouds."
  value       = merge(module.gcp.workload_private_ips, module.aws.workload_private_ips, module.azure.workload_private_ips)
}

output "workload_external_ips" {
  description = "External IPs by workload across all configured clouds."
  value       = merge(module.gcp.workload_public_ips, module.aws.workload_public_ips, module.azure.workload_public_ips)
}

output "workload_network_tags" {
  description = "GCP network tags by workload."
  value       = module.gcp.workload_network_tags
}

output "workload_service_account_emails" {
  description = "GCP service-account emails by workload."
  value       = module.gcp.workload_service_account_emails
}

output "secret_ids" {
  description = "GCP Secret Manager container IDs created from the project configuration."
  value       = module.gcp.secret_ids
}

output "secret_resource_names" {
  description = "Fully qualified GCP Secret Manager resource names by secret ID."
  value       = module.gcp.secret_resource_names
}

output "workload_secret_access" {
  description = "Secret IDs each GCP workload service account may read."
  value       = module.gcp.workload_secret_access
}

output "aws_secret_arns" {
  description = "AWS Secrets Manager ARNs by logical secret ID. Secret values are never exposed."
  value       = module.aws.secret_arns
}

output "aws_workload_secret_access" {
  description = "Secret IDs each AWS workload instance role may read."
  value       = module.aws.workload_secret_access
}

output "azure_key_vault_uri" {
  description = "Azure Key Vault URI, or null when no Azure VMs are configured."
  value       = module.azure.key_vault_uri
}

output "azure_secret_resource_ids" {
  description = "Azure Key Vault secret resource IDs by logical secret ID."
  value       = module.azure.secret_resource_ids
}

output "azure_workload_secret_access" {
  description = "Secret IDs each Azure VM managed identity may read."
  value       = module.azure.workload_secret_access
}

output "gcp_monitoring" {
  description = "GCP observability resource identifiers, or null when monitoring is disabled."
  value       = module.gcp.monitoring
}

output "gcp_kubernetes" {
  description = "K3s and Artifact Registry values for the GCP deployment, or null when disabled."
  value       = module.gcp.kubernetes
}

output "gcp_gke" {
  description = "GKE connection and ingress values, or null when GKE mode is disabled."
  value       = module.gcp.gke
}

output "aws_monitoring" {
  description = "AWS CloudWatch and SNS resource identifiers, or null when monitoring is disabled."
  value       = module.aws.monitoring_summary
}

output "aws_kubernetes" {
  description = "AWS EKS connection and ECR values, or null when EKS mode is disabled."
  value       = module.aws.kubernetes
}

output "azure_monitoring" {
  description = "Azure Monitor resource identifiers, or null when monitoring is disabled."
  value       = module.azure.monitoring_summary
}

output "database_connection" {
  description = "Database connection values for the cloud selected by default_cloud."
  value = {
    gcp   = module.gcp.database_connection
    aws   = module.aws.database_connection
    azure = module.azure.database_connection
  }[local.config.default_cloud]
}

output "gcp_database_connection" {
  description = "Deprecated compatibility output. Use database_connection."
  value       = module.gcp.database_connection
}

output "messaging_connection" {
  description = "Messaging connection values for the cloud selected by default_cloud."
  value = {
    gcp   = module.gcp.messaging_connection
    aws   = module.aws.messaging_connection
    azure = module.azure.messaging_connection
  }[local.config.default_cloud]
}

output "session_connection" {
  description = "UI session-store connection values for the cloud selected by default_cloud."
  value = {
    gcp   = module.gcp.session_connection
    aws   = module.aws.session_connection
    azure = module.azure.session_connection
  }[local.config.default_cloud]
}
