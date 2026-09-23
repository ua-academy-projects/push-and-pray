output "resource_group_name" {
  value = module.resource_group.name
}
output "managed_db_private_ip" {
  value = module.postgres.endpoint
}