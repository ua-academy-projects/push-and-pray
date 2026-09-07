output "names" {
  value = module.vm.names
}

output "internal_ips" {
  value = module.vm.internal_ips
}

output "public_ips" {
  value = module.vm.public_ips
}

output "network_tags" {
  value = module.vm.network_tags
}

output "service_account_emails" {
  value = module.iam.service_account_emails
}

output "secret_ids" {
  value = module.secrets.secret_ids
}

output "secret_resource_names" {
  value = module.secrets.secret_resource_names
}
