locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  aws_workload_vms = {
    for name, vm in var.selected_vms : name => vm
    if !contains(vm.roles, "bastion")
  }

  all_aws_secret_ids = distinct(flatten([
    for workload in values(local.aws_workload_vms) : values(workload.secret_mappings)
  ]))
}
