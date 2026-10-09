output "management_subnet_ids" {
  description = "AWS management subnet IDs keyed by abstract location."
  value       = { for location, subnet in aws_subnet.management : location => subnet.id }
}

output "workload_subnet_ids" {
  description = "AWS workload subnet IDs keyed by abstract location."
  value       = { for location, subnet in aws_subnet.workload : location => subnet.id }
}

output "kubernetes_subnet_ids" {
  value = local.managed_kubernetes_enabled ? [
    aws_subnet.workload[var.config.default_location].id,
    aws_subnet.kubernetes_secondary[0].id,
  ] : []
  depends_on = [aws_route_table_association.workload, aws_route_table_association.kubernetes_secondary, aws_route.workload_internet]
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

output "default_vpc_id" {
  description = "VPC ID in the default location, used by the single managed database."
  value       = try(aws_vpc.main[var.config.default_location].id, null)
}

output "database_subnet_ids" {
  description = "Private subnet IDs for the managed RDS database."
  value       = [for subnet in aws_subnet.database : subnet.id]
}

output "managed_database_client_security_group_ids" {
  description = "Security groups permitted to connect to managed PostgreSQL."
  value = local.managed_database_enabled ? {
    for key, instance in local.role_instances : instance.role => aws_security_group.role[key].id
    if contains(["k3s_server", "k3s_agent"], instance.role)
    && instance.location == var.config.default_location
  } : {}
}
