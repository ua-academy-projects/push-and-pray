output "vpc_id" {
    value = try(aws_vpc.main[0].id, null)
}

output "management_subnet_id" {
    value = try(aws_subnet.management[0].id, null)
}

output "workload_subnet_id" {
    value = try(aws_subnet.workload[0].id, null)
}

output "database_subnet_ids" {
    value = aws_subnet.database[*].id
}