output "vms" {
  description = "AWS workload VMs, keyed by name."
  value = {
    for name, instance in aws_instance.workload : name => {
      name        = "${local.resource_prefix}-${name}"
      internal_ip = instance.private_ip
      public_ip   = local.aws_vms[name].assign_public_ip ? aws_eip.public[name].public_ip : null
      role_arn    = aws_iam_role.ec2_role[name].arn
      role_name   = aws_iam_role.ec2_role[name].name
    }
  }
}

output "aws_vms" {
  description = "Resolved AWS VM configuration (post cloud/size/image resolution), keyed by name."
  value       = local.aws_vms
}
