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
    for name, vm in var.config.vms : name => merge(vm, {
      location = lookup(vm, "location", var.config.default_location)
      region   = var.config.locations[lookup(vm, "location", var.config.default_location)].aws.region
    })
    if lookup(vm, "cloud", var.config.default_cloud) == "aws"
  }

  bastion_location = lookup(var.config.bastion, "location", var.config.default_location)
  bastion_vms = lookup(var.config.bastion, "cloud", var.config.default_cloud) == "aws" ? {
    bastion = merge(var.config.bastion, {
      location        = local.bastion_location
      region          = var.config.locations[local.bastion_location].aws.region
      secret_mappings = {}
    })
  } : {}

  vms = merge(local.workload_vms, local.bastion_vms)

  secret_access = {
    for access in flatten([
      for vm_name, vm in local.vms : [
        for secret_id in distinct(values(vm.secret_mappings)) : {
          key        = "${vm_name}/${secret_id}"
          vm_name    = vm_name
          secret_id  = secret_id
          secret_key = "${vm.region}/${secret_id}"
          region     = vm.region
        }
      ]
    ]) : access.key => access
  }

  secret_keys = toset([
    for access in values(local.secret_access) : access.secret_key
  ])

  k3s_secret_keys = (
    var.config.deployment_mode == "k3s"
    && var.config.default_cloud == "aws"
    ) ? toset([
      for secret_id in distinct(values(var.config.k3s.secret_mappings)) :
      "${var.config.locations[var.config.default_location].aws.region}/${secret_id}"
  ]) : toset([])

  secrets = {
    for secret_key in setunion(local.secret_keys, local.k3s_secret_keys) : secret_key => {
      region    = split("/", secret_key)[0]
      secret_id = split("/", secret_key)[1]
    }
  }
}
