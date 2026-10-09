output "workload_subnet_id" {
  value = try(aws_subnet.workload[0].id, null)
}

output "vpc_id" {
  value = try(aws_vpc.main[0].id, null)
}

output "rds_subnet_ids" {
  value = local.rds_enabled ? [
    aws_subnet.rds_primary[0].id,
    aws_subnet.rds_secondary[0].id
  ] : []
}

output "eks_subnet_ids" {
  value = local.eks_enabled ? [
    aws_subnet.workload[0].id,
    aws_subnet.eks_secondary[0].id
  ] : []
}

output "security_group_ids" {
  value = {
    kubernetes = try(aws_security_group.kubernetes[0].id, null)
  }
}
