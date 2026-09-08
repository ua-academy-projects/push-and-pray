locals {
  context = {
    resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
    labels = merge(
      {
        application = var.config.name_prefix
        environment = var.config.environment
        managed_by  = "terraform"
      },
      var.config.common_labels,
    )
  }

  vms = {
    for name, vm in var.config.vms : name => vm
    if lookup(vm, "cloud", var.config.default_cloud) == "gcp"
  }

  secret_access = {
    for access in flatten([
      for vm_name, vm in local.vms : [
        for secret_id in distinct(values(vm.secret_mappings)) : {
          key       = "${vm_name}/${secret_id}"
          vm_name   = vm_name
          secret_id = secret_id
        }
      ]
    ]) : access.key => access
  }

  secret_ids = toset([
    for access in values(local.secret_access) : access.secret_id
  ])
}
