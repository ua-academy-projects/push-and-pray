locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  vms = {
    for name, vm in var.config.vms : name => vm
    if lookup(vm, "cloud", var.config.default_cloud) == "aws"
  }

  tags = {
    for name, vm in local.vms : name => merge(
      var.config.common_labels,
      try(vm.labels, {}),
      {
        Name        = "${local.resource_prefix}-${name}"
        application = var.config.name_prefix
        environment = var.config.environment
        managed_by  = "terraform"
        role        = vm.role
      },
    )
  }

  cloud_config = {
    users = concat(["default"], [
      for username, public_key in var.config.ssh_users : {
        name                = username
        groups              = ["sudo"]
        shell               = "/bin/bash"
        sudo                = "ALL=(ALL) NOPASSWD:ALL"
        lock_passwd         = true
        ssh_authorized_keys = [trimspace(public_key)]
      }
    ])
    ssh_pwauth   = false
    disable_root = true
  }
}
