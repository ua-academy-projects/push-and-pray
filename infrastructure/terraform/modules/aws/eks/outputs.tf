output "enabled" {
  description = "Whether this configuration selects a managed EKS cluster on AWS."
  value       = local.enabled
}

output "cluster_name" {
  description = "Name of the EKS cluster; null outside managed Kubernetes mode."
  value       = try(aws_eks_cluster.this[0].name, null)
}

output "endpoint" {
  description = "Kubernetes API endpoint AWS publishes for the cluster; null outside managed Kubernetes mode. This replaces kubernetes.api_endpoint, which is a name this project would have to publish itself."
  value       = try(aws_eks_cluster.this[0].endpoint, null)
}

output "certificate_authority_data" {
  description = "Base64 cluster CA the kubeconfig trusts; null outside managed Kubernetes mode."
  value       = try(aws_eks_cluster.this[0].certificate_authority[0].data, null)
}

output "vpc_id" {
  description = "VPC the cluster runs in; null outside managed Kubernetes mode. The load balancer controller is given this rather than left to discover it from instance metadata."
  value       = local.enabled ? var.network.vpc_id : null
}

output "cluster_security_group_id" {
  description = "Security group EKS creates and attaches to every node and pod network interface. Database access is granted to this group, and the load balancer controller adds its own rules to it."
  value       = try(aws_eks_cluster.this[0].vpc_config[0].cluster_security_group_id, null)
}

output "node_group_name" {
  description = "Name of the single managed node group; null outside managed Kubernetes mode."
  value       = try(aws_eks_node_group.this[0].node_group_name, null)
}

output "node_role_name" {
  description = "Name of the node instance role; null outside managed Kubernetes mode."
  value       = try(aws_iam_role.node[0].name, null)
}

output "node_role_arn" {
  description = "ARN of the node instance role; null outside managed Kubernetes mode."
  value       = try(aws_iam_role.node[0].arn, null)
}

output "registry_refresh_role_name" {
  description = "Name of the role the in-cluster registry credential refresh assumes through EKS Pod Identity. The registry module grants it its permissions, as it does for the k3s node role."
  value       = try(aws_iam_role.registry_refresh[0].name, null)
}

output "oidc_identity_provider" {
  description = "Name of the API server's OIDC identity provider configuration, or null when the operator console does not use OIDC. On k3s this is a drop-in file applied by configure_k3s_oidc; here the control plane is not reachable that way."
  value       = try(aws_eks_identity_provider_config.console[0].oidc[0].identity_provider_config_name, null)
}
