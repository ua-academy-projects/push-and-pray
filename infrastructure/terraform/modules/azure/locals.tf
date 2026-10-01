locals {
  config    = var.config
  cloud_key = "azure"

  resource_prefix = "${local.config.name_prefix}-${local.config.environment}"
  location        = local.config.regions[local.config.default_region][local.cloud_key].location

  common_labels = merge(
    local.config.common_labels,
    {
      application = local.config.name_prefix
      environment = local.config.environment
      managed_by  = "terraform"
      cloud       = local.cloud_key
    },
  )

  effective_cloud_by_vm = {
    for name, vm in local.config.vms :
    name => lookup(vm, "cloud", local.config.default_cloud)
  }

  configured_infrastructure_vm_name = local.config.service_placement[local.cloud_key].infrastructure_host

  selected_raw_vms = {
    for name, vm in local.config.vms : name => vm
    if local.effective_cloud_by_vm[name] == local.cloud_key && (
      local.config.database.mode != "managed" ||
      vm.role != "database" ||
      name == local.configured_infrastructure_vm_name
    )
  }

  resolved_vms = {
    for name, vm in local.selected_raw_vms : name => merge(vm, {
      effective_cloud = local.effective_cloud_by_vm[name]
      location        = local.config.regions[vm.region][local.cloud_key]
      instance_type   = local.config.sizes[vm.size][local.cloud_key]
      disk_type       = local.config.disk_types[vm.boot_disk.type][local.cloud_key]
      image_config    = local.config.images[vm.image][local.cloud_key]
    })
  }

  has_vms = length(local.resolved_vms) > 0

  workload_vms = {
    for name, vm in local.resolved_vms : name => vm
    if vm.role != "bastion"
  }

  network_config = local.config.network[local.cloud_key]
  bastion_vm     = one([for vm in values(local.resolved_vms) : vm if vm.role == "bastion"])

  ui_vm = try(one([
    for vm in values(local.resolved_vms) : vm
    if vm.role == "ui"
  ]), null)

  database_mode = local.config.database.mode
  database_vm_name = try(one([
    for name, vm in local.resolved_vms : name
    if vm.role == "database"
  ]), null)
  managed_database_enabled = local.has_vms && local.database_mode == "managed"
  infrastructure_vm_name = (
    local.database_mode == "managed"
    ? local.configured_infrastructure_vm_name
    : local.database_vm_name
  )

  monitoring_config  = lookup(local.config, "monitoring", {})
  monitoring_enabled = local.has_vms && lookup(local.monitoring_config, "enabled", false)
  monitoring_settings = {
    notification_email = lookup(local.monitoring_config, "notification_email", "")
    cpu = merge(
      { threshold_percent = 80, duration_seconds = 300 },
      lookup(local.monitoring_config, "cpu", {}),
    )
    disk = merge(
      { threshold_percent = 85, duration_seconds = 600 },
      lookup(local.monitoring_config, "disk", {}),
    )
    uptime = merge(
      { enabled = false, path = "/", period_seconds = 60, timeout_seconds = 10 },
      lookup(local.monitoring_config, "uptime", {}),
    )
    logs = merge(
      { enabled = false, error_pattern = "ERROR" },
      lookup(local.monitoring_config, "logs", {}),
    )
    budget = merge(
      { enabled = false, amount = 0, currency = "USD", thresholds = [] },
      lookup(local.monitoring_config, "budget", {}),
    )
  }

  all_secret_ids = distinct(flatten([
    for vm in values(local.workload_vms) : values(vm.secret_mappings)
  ]))

  active_secret_mappings_by_vm = {
    for name, workload in local.workload_vms : name => {
      for environment_name, secret_id in workload.secret_mappings :
      environment_name => secret_id
      if local.database_mode == "self_managed" ? (
        !contains(["RABBITMQ_PASSWORD", "REDIS_PASSWORD"], environment_name)
        ) : (
        environment_name == "POSTGRES_PASSWORD" ? workload.role == "history" :
        environment_name == "RABBITMQ_PASSWORD" ? (
          contains(["history", "fetcher"], workload.role) || name == local.infrastructure_vm_name
        ) :
        environment_name == "REDIS_PASSWORD" ? (
          workload.role == "ui" || name == local.infrastructure_vm_name
        ) : true
      )
    }
  }

  secret_ids_by_vm = {
    for name, mappings in local.active_secret_mappings_by_vm :
    name => distinct(values(mappings))
  }

  managed_database_secret_ids = toset(flatten([
    for mappings in values(local.active_secret_mappings_by_vm) : [
      for environment_name, secret_id in mappings : secret_id
      if environment_name == "POSTGRES_PASSWORD"
    ]
  ]))

  rabbitmq_secret_ids = toset(flatten([
    for mappings in values(local.active_secret_mappings_by_vm) : [
      for environment_name, secret_id in mappings : secret_id
      if environment_name == "RABBITMQ_PASSWORD"
    ]
  ]))

  redis_secret_ids = toset(flatten([
    for mappings in values(local.active_secret_mappings_by_vm) : [
      for environment_name, secret_id in mappings : secret_id
      if environment_name == "REDIS_PASSWORD"
    ]
  ]))
}
