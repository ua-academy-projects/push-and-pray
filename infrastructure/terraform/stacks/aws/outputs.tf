output "vms" {
  value = module.aws.vms

  precondition {
    condition     = module.aws.configuration_valid
    error_message = "The project configuration is invalid. Versioned AWS deployments require every VM provider and managed database provider to match cloud_provider=aws."
  }
}
output "managed_database" { value = coalesce(module.aws.managed_database, { enabled = false, cloud = null, host = null, port = null, name = null, user = null }) }
output "workload_external_ips" {
  value = { for name, vm in module.aws.vms : name => vm.public_ip if vm.role != "bastion" }
}
output "workload_internal_ips" {
  value = { for name, vm in module.aws.vms : name => vm.internal_ip if vm.role != "bastion" }
}
output "secret_ids" { value = module.aws.secret_ids }
output "workload_secret_access" { value = module.aws.workload_secret_access }
output "managed_service_images" { value = { aws = module.aws.managed_service_images } }

output "deployment" {
  description = "Versioned provider-neutral deployment contract."
  value       = module.deployment_contract.deployment
}
