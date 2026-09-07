locals {
  aws_vms = {
    for name in keys(var.vms) : name => var.config.vms[name]
  }

  all_secret_ids = distinct(flatten([
    for vm in values(local.aws_vms) : values(vm.secret_mappings)
  ]))

  vms_with_secrets = {
    for name, vm in local.aws_vms : name => distinct(values(vm.secret_mappings))
    if length(vm.secret_mappings) > 0
  }

  common_labels = {
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
  }
}
