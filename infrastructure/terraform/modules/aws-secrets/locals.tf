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
    for name, vm in var.config.vms : name => merge(vm, {
      location = lookup(vm, "location", var.config.default_location)
      region   = var.config.locations[lookup(vm, "location", var.config.default_location)].aws.region
    })
    if lookup(vm, "cloud", var.config.default_cloud) == "aws"
  }

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

  secrets = {
    for secret_key in local.secret_keys : secret_key => {
      region    = split("/", secret_key)[0]
      secret_id = split("/", secret_key)[1]
    }
  }
}
