locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  roles = {
    for name, vm in var.config.vms : name => vm
    if lookup(vm, "cloud", var.config.default_cloud) == "aws" && vm.role != "bastion"
  }

  secret_ids = toset(flatten([
    for vm in values(local.roles) :
    values(vm.secret_mappings)
  ]))

  secret_readers = {
    for name, vm in local.roles : name => toset(values(vm.secret_mappings))
    if length(vm.secret_mappings) > 0
  }

  tags = {
    for name, vm in local.roles : name => merge(
      var.config.common_labels,
      try(vm.labels, {}),
      {
        Name = "${local.resource_prefix}-${name}-runtime"
        role = vm.role
      },
    )
  }
}
