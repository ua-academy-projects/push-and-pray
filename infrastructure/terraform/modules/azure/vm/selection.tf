locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
  ssh_user        = one(keys(var.config.ssh_users))
  vms = {
    for name, vm in var.config.vms : name => merge(
      { location = var.config.default_location, assign_public_ip = false, disks = [] },
      var.config.vm_defaults,
      vm,
      {
        bootstrap_commands = try(vm.bootstrap.commands, var.config.vm_defaults.bootstrap.commands, [])
        disks              = [for disk in try(vm.disks, []) : merge({ type = "standard" }, disk)]
      },
    )
    if try(vm.cloud, var.config.default_cloud) == "azure" && contains(keys(var.workload_subnet_ids), try(vm.location, var.config.default_location))
  }
  labels_by_vm = {
    for name, vm in local.vms : name => merge(
      var.config.common_labels, try(vm.labels, {}),
      { environment = var.config.environment, role = vm.role },
    )
  }
  bootstrap_scripts = {
    for name, vm in local.vms : name => length(vm.bootstrap_commands) > 0 ? base64encode(join("\n", concat(
      ["#!/usr/bin/env bash", "set -euo pipefail", ""],
      vm.bootstrap_commands,
      [""],
    ))) : null
  }
  data_disks = {
    for disk in flatten([
      for name, vm in local.vms : [
        for index, disk in vm.disks : {
          key       = "${name}-data-${index + 1}"
          vm_name   = name
          lun       = index
          disk_type = disk.type
          disk_size = disk.size
          location  = vm.location
        }
      ]
    ]) : disk.key => disk
  }
}
