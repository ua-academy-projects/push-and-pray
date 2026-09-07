output "vms" {
  description = "VM resource attributes keyed by project VM key."
  value = {
    for name, instance in aws_instance.workload : name => {
      name          = instance.tags["Name"]
      instance_id   = instance.id
      internal_ip   = instance.private_ip
      public_ip     = try(aws_eip.public[name].public_ip, null)
      role          = local.resolved_vms[name].role
      tags          = instance.tags
      iam_role_name = aws_iam_role.workload[name].name
      iam_role_arn  = aws_iam_role.workload[name].arn
    }
  }
}

output "resolved_vms" {
  description = "Provider-resolved VM configuration, independent of created resources."
  value       = local.resolved_vms
}
