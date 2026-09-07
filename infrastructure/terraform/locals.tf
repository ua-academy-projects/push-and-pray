locals {
  config = jsondecode(file(var.project_config_path))

  workload_vms = {
    for name, vm in local.config.vms : name => vm
    if vm.role != "bastion"
  }
}
