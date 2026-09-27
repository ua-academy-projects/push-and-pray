locals {
  cloud_name = "aws"
  vms = {
    for name, vm in var.config.vms : name => vm
    if lookup(vm, "cloud", var.config.default_cloud) == local.cloud_name
  }
  workload_vms = {
    for name, vm in local.vms : name => vm
    if vm.role != "bastion"
  }
  secret_ids = toset(distinct(flatten([
    for vm in values(local.workload_vms) : values(vm.secret_mappings)
  ])))
  common_tags = merge(var.config.common_labels, {
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
    cloud       = local.cloud_name
  })
}
