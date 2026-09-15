locals {
  profile = try(var.config.clouds[var.cloud], null)

  cloud_vms = {
    for name, vm in var.config.vms : name => vm
    if try(vm.cloud, var.config.default_cloud) == var.cloud
  }

  is_active = length(local.cloud_vms) > 0

  workload_vms = {
    for name, vm in local.cloud_vms : name => vm
    if local.is_active
  }

  # Where PostgreSQL runs is decided once for the whole project, but only the
  # cloud hosting the infra VM builds the managed instance: that VM carries the
  # broker and the cache the workloads pair with it, and there is no
  # cross-cloud networking to reach a database anywhere else.
  database_managed = try(var.config.database.mode, "self-hosted") == "managed"

  hosts_infra = length([
    for name, vm in local.cloud_vms : name
    if vm.role == "infra"
  ]) > 0

  builds_database = local.is_active && local.database_managed && local.hosts_infra

  database_size = try(
    var.config.clouds[var.cloud].database_sizes[var.config.database.size],
    null,
  )

  common_labels = merge(
    {
      application = var.config.name_prefix
      environment = var.config.environment
      managed_by  = "terraform"
    },
    var.config.common_labels,
    {
      cloud = var.cloud
    },
  )
}
