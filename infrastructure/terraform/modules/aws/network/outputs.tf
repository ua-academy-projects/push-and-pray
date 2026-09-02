output "management_subnet_ids" {
  description = "AWS management subnet IDs keyed by abstract location."
  value       = { for location, subnet in aws_subnet.management : location => subnet.id }
}

output "workload_subnet_ids" {
  description = "AWS workload subnet IDs keyed by abstract location."
  value       = { for location, subnet in aws_subnet.workload : location => subnet.id }
}

output "security_group_ids" {
  description = "AWS security group IDs keyed by abstract location and VM role."
  value = {
    for location in keys(local.vms_by_location) : location => {
      for key, instance in local.role_instances :
      instance.role => aws_security_group.role[key].id if instance.location == location
    }
  }
}
