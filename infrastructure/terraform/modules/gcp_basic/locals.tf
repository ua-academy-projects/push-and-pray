locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  service_accounts = {
    for name, vm in var.config.vms : name => vm
    if lookup(vm, "cloud", var.config.default_cloud) == "gcp" && vm.role != "bastion"
  }

  secret_ids = toset(flatten([
    for account in values(local.service_accounts) :
    values(account.secret_mappings)
  ]))

  secret_version_writers = {
    for pair in setproduct(
      local.secret_ids,
      toset(var.config.secret_version_managers)
    ) :
    "${pair[0]}/${pair[1]}" => {
      secret_id = pair[0]
      member    = pair[1]
    }
  }
}
