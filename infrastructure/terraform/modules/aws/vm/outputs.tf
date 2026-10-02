output "vms" {
  description = "AWS k3s nodes, keyed by name."
  value = {
    for name, instance in aws_instance.workload : name => {
      instance_id = instance.id
      name        = "${var.config.name_prefix}-${var.config.environment}-${name}"
      internal_ip = instance.private_ip
      public_ip   = local.aws_vms[name].assign_public_ip ? aws_eip.public[name].public_ip : null
    }
  }
}

output "node_role_name" {
  description = "Name of the shared instance role every node runs as; null outside AWS."
  value       = try(aws_iam_role.node[0].name, null)
}

output "node_role_arn" {
  description = "ARN of the shared instance role every node runs as; null outside AWS."
  value       = try(aws_iam_role.node[0].arn, null)
}
