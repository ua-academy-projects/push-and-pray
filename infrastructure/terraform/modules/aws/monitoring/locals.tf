locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
  common_labels = {
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
  }
  settings              = var.config.monitoring
  region                = var.config.region_map[var.config.region].aws.region
  workload_vms          = { for name, vm in var.vms : name => vm if var.config.vms[name].role != "bastion" }
  enabled               = local.settings.enabled && (length(local.workload_vms) > 0 || local.synthetics_enabled || local.database_enabled)
  logs_enabled          = local.enabled && local.settings.logs_enabled && length(local.ui_vms) > 0
  alarms_enabled        = local.enabled && local.settings.alarms_enabled
  agent_enabled         = local.enabled && local.settings.agent_metrics_enabled
  synthetics_enabled    = local.settings.enabled && local.settings.synthetics.enabled && (local.settings.synthetics.clouds == null ? length(local.workload_vms) > 0 : contains(local.settings.synthetics.clouds, "aws"))
  recipients            = local.enabled ? local.settings.email_recipients : toset([])
  notifications_enabled = local.enabled && length(local.recipients) > 0
  log_group_name        = "/${var.config.name_prefix}/${var.config.environment}/traefik"
  http_namespace        = "${local.resource_prefix}/HTTP"
  canary_name           = "${substr(local.resource_prefix, 0, 11)}-${substr(sha256(local.resource_prefix), 0, 4)}-health"
  ui_vms                = { for name, vm in local.workload_vms : name => vm if var.config.vms[name].role == "ui" }
  signals = merge({
    cpu    = { namespace = "AWS/EC2", metric = "CPUUtilization", stat = "Average", threshold = local.settings.cpu_threshold_percent, period = 300, comparison = "GreaterThanOrEqualToThreshold", missing = "missing" }
    status = { namespace = "AWS/EC2", metric = "StatusCheckFailed", stat = "Maximum", threshold = 1, period = 60, comparison = "GreaterThanOrEqualToThreshold", missing = "breaching" }
    }, local.agent_enabled ? {
    memory        = { namespace = "CWAgent", metric = "mem_used_percent", stat = "Average", threshold = local.settings.memory_threshold_percent, period = 300, comparison = "GreaterThanOrEqualToThreshold", missing = "missing" }
    disk          = { namespace = "CWAgent", metric = "disk_used_percent", stat = "Maximum", threshold = local.settings.disk_threshold_percent, period = 300, comparison = "GreaterThanOrEqualToThreshold", missing = "missing" }
    agent_missing = { namespace = "CWAgent", metric = "mem_used_percent", stat = "Minimum", threshold = 0, period = 300, comparison = "LessThanThreshold", missing = "breaching" }
  } : {})
  vm_signals = merge({}, [for name, vm in local.workload_vms : {
    for signal, definition in local.signals : "${name}-${signal}" => merge(definition, {
      vm_name    = name
      signal     = signal
      dimensions = merge({ InstanceId = vm.instance_id }, signal == "disk" ? { path = "/", fstype = local.settings.disk_fstype } : {})
    })
  }]...)
  http_filters = {
    HTTP500Count = "{ $.DownstreamStatus = 500 }"
    HTTP5xxCount = "{ $.DownstreamStatus >= 500 && $.DownstreamStatus < 600 }"
  }
}

locals {
  database_enabled      = local.settings.enabled && local.settings.database_metrics_enabled && var.database != null
  application_enabled   = local.settings.enabled && local.settings.application_metrics_enabled && length(local.workload_vms) > 0
  service_logs_enabled  = local.settings.enabled && local.settings.service_logs_enabled && length(local.workload_vms) > 0
  application_namespace = "${local.resource_prefix}/Application"
  application_log_group = "/${var.config.name_prefix}/${var.config.environment}/application"
}
