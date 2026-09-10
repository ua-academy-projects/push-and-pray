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
    if try(vm.cloud, var.config.default_cloud) == "gcp" && contains(keys(var.workload_subnet_ids), vm.location)
  }

  bootstrap_scripts = {
    for name, vm in local.vms : name => length(vm.bootstrap_commands) > 0 ? join("\n", concat(
      [
        "#!/usr/bin/env bash",
        "set -euo pipefail",
        "",
        "readonly marker=/var/lib/oilscope/custom-bootstrap-complete",
        "if [[ -f \"$marker\" ]]; then",
        "  exit 0",
        "fi",
        "",
      ],
      vm.bootstrap_commands,
      [
        "",
        "install -d -m 0755 /var/lib/oilscope",
        "touch \"$marker\"",
        "",
      ],
    )) : null
  }

  data_disks = {
    for disk in flatten([
      for vm_name, vm in local.vms : [
        for disk_index, disk in vm.disks : {
          key        = "${vm_name}-data-${disk_index + 1}"
          vm_name    = vm_name
          disk_index = disk_index
          disk_type  = disk.type
          disk_size  = disk.size
          location   = vm.location
        }
      ]
    ]) : disk.key => disk
  }
}
