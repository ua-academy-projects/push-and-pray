locals {
  config = jsondecode(file(var.project_config_path))

  enabled_clouds = toset([
    for vm in values(local.config.vms) :
    lookup(vm, "cloud", local.config.default_cloud)
  ])
}
