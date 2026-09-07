output "management_subnet_id" {
  value = try(aws_subnet.management[0].id, null)
}

output "workload_subnet_id" {
  value = try(aws_subnet.workload[0].id, null)
}

output "security_group_ids" {
  value = {
    bastion  = try(aws_security_group.bastion[0].id, null)
    database = try(aws_security_group.database[0].id, null)
    history  = try(aws_security_group.history[0].id, null)
    fetcher  = try(aws_security_group.fetcher[0].id, null)
    ui       = try(aws_security_group.ui[0].id, null)
  }
}
