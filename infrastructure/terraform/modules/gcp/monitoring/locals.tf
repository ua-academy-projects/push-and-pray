locals {
  resource_prefix    = "${var.config.name_prefix}-${var.config.environment}"
  common_labels      = { application = var.config.name_prefix, environment = var.config.environment, managed_by = "terraform" }
  project_id         = try(var.config.clouds.gcp.project_id, null)
  settings           = var.config.monitoring
  enabled            = local.settings.enabled && length(var.vms) > 0
  ui_vms             = { for name, vm in var.vms : name => vm if var.config.vms[name].role == "ui" }
  logs_enabled       = local.enabled && local.settings.logs_enabled && length(local.ui_vms) > 0
  alarms_enabled     = local.enabled && local.settings.alarms_enabled
  agent_enabled      = local.enabled && local.settings.agent_metrics_enabled
  synthetics_enabled = local.enabled && local.settings.synthetics.enabled
  recipients         = local.enabled ? local.settings.email_recipients : toset([])
  vm_filters         = { for name, vm in var.vms : name => "resource.type=\"gce_instance\" AND resource.labels.project_id=\"${local.project_id}\" AND resource.labels.instance_id=\"${vm.instance_id}\" AND resource.labels.zone=\"${vm.zone}\"" }
  access_filter      = "resource.type=\"gce_instance\" AND log_id(\"oilscope_access\") AND (${length(local.ui_vms) > 0 ? join(" OR ", [for vm in values(local.ui_vms) : "resource.labels.instance_id=\"${vm.instance_id}\""]) : "FALSE"})"
  signals = merge({
    cpu = { metric = "compute.googleapis.com/instance/cpu/utilization", extra = "", threshold = local.settings.cpu_threshold_percent / 100, aligner = "ALIGN_MEAN" }
    }, local.agent_enabled ? {
    memory = { metric = "agent.googleapis.com/memory/percent_used", extra = " AND metric.labels.state=\"used\"", threshold = local.settings.memory_threshold_percent, aligner = "ALIGN_MEAN" }
    disk   = { metric = "agent.googleapis.com/disk/percent_used", extra = " AND metric.labels.state=\"used\"", threshold = local.settings.disk_threshold_percent, aligner = "ALIGN_MAX" }
  } : {})
  vm_signals = merge({}, [for name, vm in var.vms : { for signal, definition in local.signals : "${name}-${signal}" => merge(definition, { name = name, signal = signal, filter = "${local.vm_filters[name]} AND metric.type=\"${definition.metric}\"${definition.extra}" }) }]...)
  absence_signals = merge({}, [for name, vm in var.vms : merge({
    "${name}-vm-missing" = { name = name, filter = "${local.vm_filters[name]} AND metric.type=\"compute.googleapis.com/instance/uptime\"" }
    }, local.agent_enabled ? {
    "${name}-agent-missing" = { name = name, filter = "${local.vm_filters[name]} AND metric.type=\"agent.googleapis.com/memory/percent_used\" AND metric.labels.state=\"used\"" }
  } : {})]...)
  http_filters          = { HTTP500Count = "jsonPayload.DownstreamStatus=500", HTTP5xxCount = "jsonPayload.DownstreamStatus>=500 AND jsonPayload.DownstreamStatus<600" }
  notification_channels = [for channel in google_monitoring_notification_channel.email : channel.name]
}
