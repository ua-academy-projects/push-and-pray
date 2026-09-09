locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  merged_common_labels = merge(
    {
        Application = var.config.name_prefix
        Environment = var.config.environment
        Managed_by  = "terraform"
    },
    var.config.common_labels,
  )

  selected_vms = {
    for name, vm in var.config.vms : name => vm
    if coalesce(try(vm.cloud, null), var.config.cloud) == "gcp"
  }

  bastion_startup_scripts = {
    for name, vm in local.selected_vms : name => templatefile("${path.module}/templates/bastion-startup.sh.tftpl", {
      ssh_port = vm.ssh_port
    })
    if vm.role == "bastion"
  }
}
