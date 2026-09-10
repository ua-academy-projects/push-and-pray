locals {
  config    = var.config
  cloud_key = "gcp"

  resource_prefix = "${local.config.name_prefix}-${local.config.environment}"

  common_labels = merge(
    {
      application = local.config.name_prefix
      environment = local.config.environment
      managed_by  = "terraform"
      cloud       = local.cloud_key
    },
    local.config.common_labels,
  )

  effective_cloud_by_vm = {
    for name, vm in local.config.vms :
    name => lookup(vm, "cloud", local.config.default_cloud)
  }

  selected_raw_vms = {
    for name, vm in local.config.vms :
    name => vm
    if(
      local.effective_cloud_by_vm[name] == local.cloud_key &&
      (
        local.database_mode != "managed" ||
        vm.role != "database"
      )
    )
  }

  resolved_vms = {
    for name, vm in local.selected_raw_vms :
    name => merge(vm, {
      effective_cloud = local.effective_cloud_by_vm[name]
      location        = local.config.regions[vm.region][local.cloud_key]
      instance_type   = local.config.sizes[vm.size][local.cloud_key]
      disk_type       = local.config.disk_types[vm.boot_disk.type][local.cloud_key]
      image_config    = local.config.images[vm.image][local.cloud_key]
    })
  }

  workload_vms = {
    for name, vm in local.resolved_vms :
    name => vm
    if vm.role != "bastion"
  }

  ui_vm = try(one([
    for vm in values(local.resolved_vms) : vm
    if vm.role == "ui"
  ]), null)

  monitoring_config  = lookup(local.config, "monitoring", {})
  monitoring_enabled = local.has_vms && lookup(local.monitoring_config, "enabled", false)
  monitoring_settings = {
    notification_email = lookup(
      local.monitoring_config,
      "notification_email",
      try(local.ui_vm.public_endpoint.acme_email, ""),
    )
    cpu = merge(
      { threshold_percent = 80, duration_seconds = 300 },
      lookup(local.monitoring_config, "cpu", {}),
    )
    disk = merge(
      { threshold_percent = 85, duration_seconds = 600 },
      lookup(local.monitoring_config, "disk", {}),
    )
    uptime = merge(
      { enabled = true, path = "/", period_seconds = 60, timeout_seconds = 10 },
      lookup(local.monitoring_config, "uptime", {}),
    )
    logs = merge(
      { enabled = true, error_pattern = "(?i)(error|exception|critical)" },
      lookup(local.monitoring_config, "logs", {}),
    )
    budget = merge(
      { enabled = false, amount = 10, currency = "USD", thresholds = [0.5, 0.9, 1.0] },
      lookup(local.monitoring_config, "budget", {}),
    )
  }

  all_secret_ids = distinct(flatten([
    for workload in values(local.workload_vms) : values(workload.secret_mappings)
  ]))

  secret_ids_by_vm = {
    for name, workload in local.workload_vms :
    name => distinct(values(workload.secret_mappings))
  }

  has_vms    = length(local.resolved_vms) > 0
  bastion_vm = local.config.vms.bastion

  database_mode = local.config.database.mode

  fetcher_vm_name = one([for name, vm in local.resolved_vms : name if vm.role == "fetcher"])
  history_vm_name = one([for name, vm in local.resolved_vms : name if vm.role == "history"])

  # In self-managed mode, exactly one workload VM must own the database role.
  # In managed mode the database VM is deliberately excluded from resolved_vms.
  database_vm_name = local.database_mode == "self_managed" ? one([
    for name, vm in local.resolved_vms : name
    if vm.role == "database"
  ]) : null
}
