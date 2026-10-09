output "profile" {
  description = "This cloud's profile from the configuration, or null when it declares none."
  value       = local.profile
}

output "is_active" {
  description = "Whether this cloud hosts any node. False means the caller builds nothing at all, its bastion included."
  value       = local.is_active
}

output "nodes" {
  description = "Nodes this cloud hosts, complete with node_defaults. Empty when the cloud is inactive."
  value       = local.nodes
}

output "hosts_server" {
  description = "Whether a k3s_server node runs on this cloud - and with it, whether the cloud holds the secrets."
  value       = local.hosts_server
}

output "remote_cidrs" {
  description = "Ranges routed through this cloud's bastion: every other cloud that hosts a node, and the tailnet."
  value       = local.remote_cidrs
}

output "cluster_cidrs" {
  description = "Sources cluster traffic may come from: the range of every cloud that hosts a node, and the tailnet."
  value       = local.cluster_cidrs
}

output "secret_ids" {
  description = "Secret containers this cloud holds: every ID in the secrets block when a k3s_server node runs here, none otherwise."
  value       = local.secret_ids
}

output "resource_prefix" {
  description = "Prefix shared by every resource name."
  value       = "${var.config.name_prefix}-${var.config.environment}"
}

output "common_labels" {
  description = "Labels or tags applied to every resource, including the cloud key the Ansible inventory selects on."
  value       = local.common_labels
}

output "cloud" {
  description = "The cloud this instance of the module answered for."
  value       = var.cloud
}
