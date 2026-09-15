locals {
  config = jsondecode(file(var.project_config_path))

  managed_database_clients = {
    for name, vm in local.config.vms : name => vm
    if length(setintersection(toset(vm.tags), toset(["infrastructure", "history", "fetcher", "ui"]))) > 0
  }
}

check "managed_database_topology" {
  assert {
    condition = local.config.database.mode != "managed" || alltrue([
      for vm in values(local.managed_database_clients) :
      lookup(vm, "cloud", local.config.default_cloud) == local.config.default_cloud &&
      lookup(vm, "location", local.config.default_location) == local.config.default_location
    ])
    error_message = "Managed database clients must use default_cloud and default_location for private connectivity."
  }
}
