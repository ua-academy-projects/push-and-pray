output "cluster_name" {
  value = try(aws_eks_cluster.main[0].name, null)
}

output "region" {
  value = var.enabled ? local.region : null
}

output "cluster_security_group_id" {
  value = try(aws_eks_cluster.main[0].vpc_config[0].cluster_security_group_id, null)
}
