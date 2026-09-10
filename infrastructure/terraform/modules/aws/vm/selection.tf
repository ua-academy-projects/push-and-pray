locals {
  vms = {
    for name, vm in var.config.vms : name => merge(
      { assign_public_ip = false, disks = [] },
      var.config.vm_defaults,
      vm,
      {
        bootstrap_commands = try(vm.bootstrap.commands, [])
        disks = [
          for disk in try(vm.disks, []) : merge({ type = "standard" }, disk)
        ]
      },
    )
    if try(vm.cloud, var.config.default_cloud) == "aws" && contains(keys(var.workload_subnet_ids), vm.location)
  }

  bootstrap_scripts = {
    for name, vm in local.vms : name => length(vm.bootstrap_commands) > 0 ? join("\n", concat(
      [
        "#!/usr/bin/env bash",
        "set -euo pipefail",
        "",
      ],
      vm.bootstrap_commands,
      [""],
    )) : null
  }

  key_pair_locations = {
    for location in keys(var.workload_subnet_ids) :
    location => var.config.locations[location].aws
  }
}
