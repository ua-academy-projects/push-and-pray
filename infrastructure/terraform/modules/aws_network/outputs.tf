output "vpc_id" {
  description = "AWS VPC ID."
  value       = aws_vpc.main.id
}

output "management_subnet_id" {
  description = "Public subnet used by internet-facing workloads."
  value       = aws_subnet.management.id
}

output "workload_subnet_id" {
  description = "Private subnet used by internal workloads."
  value       = aws_subnet.workload.id
}
