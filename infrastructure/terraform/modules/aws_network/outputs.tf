output "management_subnet_id" {
  description = "Public subnet ID for bastion and VMs with public addresses."
  value       = aws_subnet.management.id

  depends_on = [
    aws_route.management_internet,
    aws_route_table_association.management,
  ]
}

output "vm_subnet_id" {
  description = "Private subnet ID for VMs using NAT for outbound internet."
  value       = aws_subnet.vm.id

  depends_on = [
    aws_route.vm_internet,
    aws_route_table_association.vm,
    aws_route.management_internet,
    aws_route_table_association.management,
  ]
}

output "vpc_id" {
  description = "ID of the application VPC."
  value       = aws_vpc.main.id
}

output "database_subnet_ids" {
  description = "Private subnet IDs spanning the Availability Zones required by RDS."
  value       = [for zone in sort(keys(aws_subnet.database)) : aws_subnet.database[zone].id]
}

output "security_group_ids_by_role" {
  description = "Security group IDs keyed by VM role."
  value = {
    for role, group in aws_security_group.roles : role => group.id
  }

  depends_on = [
    aws_vpc_security_group_egress_rule.all,
    aws_vpc_security_group_ingress_rule.bastion_ssh,
    aws_vpc_security_group_ingress_rule.vms_ssh,
    aws_vpc_security_group_ingress_rule.ui_web,
    aws_vpc_security_group_ingress_rule.history_api,
    aws_vpc_security_group_ingress_rule.rabbitmq,
    aws_vpc_security_group_ingress_rule.redis,
  ]
}
