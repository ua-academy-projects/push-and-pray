output "vms" { value = module.aws.vms }
output "managed_database" { value = coalesce(module.aws.managed_database, { enabled = false, cloud = null, host = null, port = null, name = null, user = null }) }
output "workload_external_ips" {
  value = { for name, vm in module.aws.vms : name => vm.public_ip if vm.role != "bastion" }
}
output "workload_internal_ips" {
  value = { for name, vm in module.aws.vms : name => vm.internal_ip if vm.role != "bastion" }
}
output "secret_ids" { value = module.aws.secret_ids }
output "workload_secret_access" { value = module.aws.workload_secret_access }
