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

  workload_vms = {
    for name, vm in var.config.vms : name => vm
    if lookup(vm, "cloud", var.config.default_cloud) == "gcp"
  }

  bastion_vms = lookup(var.config.bastion, "cloud", var.config.default_cloud) == "gcp" ? {
    bastion = merge(var.config.bastion, {
      secret_mappings = {}
    })
  } : {}

  vms = merge(local.workload_vms, local.bastion_vms)

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

  vm_secret_ids = toset([
    for access in values(local.secret_access) : access.secret_id
  ])

  k3s_secret_ids = (
    try(var.config.deployment_mode, "compose") == "k3s"
    && var.config.default_cloud == "gcp"
  ) ? toset(values(try(var.config.k3s.secret_mappings, {}))) : toset([])

  secret_ids = setunion(local.vm_secret_ids, local.k3s_secret_ids)
}
