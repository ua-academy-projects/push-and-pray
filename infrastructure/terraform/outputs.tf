output "bastion_public_ips" {
  description = "Public IP of every bastion, keyed by cloud. Each cloud that hosts a node runs its own."
  value       = merge(module.gcp.bastion_public_ips, module.aws.bastion_public_ips, module.azure.bastion_public_ips)
}

output "bastion_internal_ips" {
  description = "Internal IP of every bastion, keyed by cloud. The routes to the other clouds and to the tailnet point here."
  value       = merge(module.gcp.bastion_internal_ips, module.aws.bastion_internal_ips, module.azure.bastion_internal_ips)
}

output "routed_ranges" {
  description = "The range of every cloud that hosts a node, plus the tailnet. Each bastion advertises its own cloud's range and routes the others."
  value       = local.routed_ranges
}

output "node_vm_names" {
  description = "VM names by node."
  value       = merge(module.gcp.node_vm_names, module.aws.node_vm_names, module.azure.node_vm_names)
}

output "node_roles" {
  description = "k3s role by node."
  value       = merge(module.gcp.node_roles, module.aws.node_roles, module.azure.node_roles)
}

output "node_clouds" {
  description = "Cloud hosting each node. Matches the cloud label the Ansible inventory selects on."
  value       = merge(module.gcp.node_clouds, module.aws.node_clouds, module.azure.node_clouds)
}

output "node_internal_ips" {
  description = "Internal IP by node, as the cloud assigned it from the workload subnet."
  value       = merge(module.gcp.node_internal_ips, module.aws.node_internal_ips, module.azure.node_internal_ips)
}

output "node_external_ips" {
  description = "External IP by node, or null for a node without one."
  value       = merge(module.gcp.node_external_ips, module.aws.node_external_ips, module.azure.node_external_ips)
}

output "node_identities" {
  description = "Runtime identity of each node: a service-account email on GCP, an IAM role ARN on AWS, a managed identity resource ID on Azure."
  value       = merge(module.gcp.node_identities, module.aws.node_identities, module.azure.node_identities)
}

output "secret_ids" {
  description = "Secret container IDs created from the configuration's secrets block."
  value       = sort(distinct(concat(module.gcp.secret_ids, module.aws.secret_ids, module.azure.secret_ids)))
}

output "secret_resource_names" {
  description = "Fully qualified secret resource names, by cloud and secret ID."
  value = {
    gcp   = module.gcp.secret_resource_names
    aws   = module.aws.secret_resource_names
    azure = module.azure.secret_resource_names
  }
}

output "node_secret_access" {
  description = "Secret IDs each node identity may read - only k3s_server nodes hold any. Names only - never values."
  value       = merge(module.gcp.node_secret_access, module.aws.node_secret_access, module.azure.node_secret_access)
}
