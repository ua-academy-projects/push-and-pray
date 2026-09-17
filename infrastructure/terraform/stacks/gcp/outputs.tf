output "vms" {
  value = module.gcp.vms

  precondition {
    condition     = module.gcp.configuration_valid
    error_message = "The project configuration is invalid. Versioned GCP deployments require every VM provider and managed database provider to match cloud_provider=gcp."
  }
}
output "managed_database" { value = coalesce(module.gcp.managed_database, { enabled = false, cloud = null, host = null, port = null, name = null, user = null }) }
output "workload_external_ips" {
  value = { for name, vm in module.gcp.vms : name => vm.public_ip if vm.role != "bastion" }
}
output "workload_internal_ips" {
  value = { for name, vm in module.gcp.vms : name => vm.internal_ip if vm.role != "bastion" }
}
output "secret_ids" { value = module.gcp.secret_ids }
output "workload_secret_access" { value = module.gcp.workload_secret_access }
output "managed_service_images" { value = { gcp = module.gcp.managed_service_images } }

output "deployment" {
  description = "Versioned provider-neutral deployment contract."
  value       = module.deployment_contract.deployment
}
