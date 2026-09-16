locals {
  config    = var.config
  cloud_key = "aws"

  resource_prefix = "${local.config.name_prefix}-${local.config.environment}"

  has_vms = length(local.resolved_vms) > 0

  bastion_vm = local.config.vms.bastion

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
    if local.effective_cloud_by_vm[name] == local.cloud_key
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

  # Secret mappings are cloud-neutral configuration. This AWS wrapper turns
  # their secret IDs into AWS Secret Manager containers and, below, ARNs.
  all_secret_ids = distinct(flatten([
    for vm in values(local.workload_vms) : values(vm.secret_mappings)
  ]))

  inactive_secret_names_by_role = local.database_mode == "self_managed" ? {
    for role in ["database", "history", "fetcher", "ui"] :
    role => ["RABBITMQ_PASSWORD", "REDIS_PASSWORD"]
    } : {
    database = ["POSTGRES_PASSWORD"]
    history  = ["REDIS_PASSWORD"]
    fetcher  = ["POSTGRES_PASSWORD", "REDIS_PASSWORD"]
    ui       = ["POSTGRES_PASSWORD", "RABBITMQ_PASSWORD"]
  }

  active_secret_mappings_by_vm = {
    for name, workload in local.workload_vms : name => {
      for environment_name, secret_id in workload.secret_mappings :
      environment_name => secret_id
      if !contains(local.inactive_secret_names_by_role[workload.role], environment_name)
    }
  }

  secret_ids_by_vm = {
    for name, secret_mappings in local.active_secret_mappings_by_vm :
    name => distinct(values(secret_mappings))
  }

  managed_database_secret_ids = toset(flatten([
    for secret_mappings in values(local.active_secret_mappings_by_vm) : [
      for environment_name, secret_id in secret_mappings : secret_id
      if environment_name == "POSTGRES_PASSWORD"
    ]
  ]))

  rabbitmq_secret_ids = toset(flatten([
    for secret_mappings in values(local.active_secret_mappings_by_vm) : [
      for environment_name, secret_id in secret_mappings : secret_id
      if environment_name == "RABBITMQ_PASSWORD"
    ]
  ]))

  redis_secret_ids = toset(flatten([
    for secret_mappings in values(local.active_secret_mappings_by_vm) : [
      for environment_name, secret_id in secret_mappings : secret_id
      if environment_name == "REDIS_PASSWORD"
    ]
  ]))

  # Keys are stable VM names from the JSON. The ARN values become known after
  # the Secret Manager resources are created, which is safe for IAM policies.
  secret_arns_by_vm = {
    for name, secret_ids in local.secret_ids_by_vm :
    name => compact([
      for secret_id in secret_ids :
      try(module.secrets.secret_arns[secret_id], null)
    ])
  }

  database_mode = local.config.database.mode

  database_vm_name = try(one([
    for name, vm in local.resolved_vms : name
    if vm.role == "database"
  ]), null)

  ui_vm = one([
    for _, vm in local.resolved_vms : vm
    if vm.role == "ui"
  ])
}
