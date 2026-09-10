locals {
  selected_vms = {
    for name, vm in var.config.vms : name => vm
    if coalesce(try(vm.cloud, null), var.config.cloud) == "aws"
  }

  has_selected_vms = length(local.selected_vms) > 0

  db_password_secret_id = try(
    [
      for vm in var.config.vms : vm.secret_mappings.POSTGRES_PASSWORD
      if try(vm.secret_mappings.POSTGRES_PASSWORD, null) != null
    ][0],
    null
  )

}
