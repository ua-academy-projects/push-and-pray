locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
  common_tags = {
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
  }
  settings              = var.config.monitoring
  workload_vms          = { for name, vm in var.vms : name => vm if var.config.vms[name].role != "bastion" }
  ui_vms                = { for name, vm in local.workload_vms : name => vm if var.config.vms[name].role == "ui" }
  enabled               = local.settings.enabled && (length(local.workload_vms) > 0 || local.synthetics_enabled || local.database_enabled)
  logs_enabled          = local.enabled && local.settings.logs_enabled && length(local.ui_vms) > 0
  alarms_enabled        = local.enabled && local.settings.alarms_enabled
  agent_enabled         = local.enabled && local.settings.agent_metrics_enabled
  synthetics_enabled    = local.settings.enabled && local.settings.synthetics.enabled && (local.settings.synthetics.clouds == null ? length(local.workload_vms) > 0 : contains(local.settings.synthetics.clouds, "azure"))
  recipients            = local.enabled ? local.settings.email_recipients : toset([])
  notifications_enabled = local.enabled && length(local.recipients) > 0
  action_group_ids      = local.notifications_enabled ? [azurerm_monitor_action_group.alerts[0].id] : []

  database_enabled     = local.settings.enabled && local.settings.database_metrics_enabled && var.database != null
  application_enabled  = local.settings.enabled && local.settings.application_metrics_enabled && length(local.workload_vms) > 0
  service_logs_enabled = local.settings.enabled && local.settings.service_logs_enabled && length(local.workload_vms) > 0

  agent_required    = local.enabled && (local.agent_enabled || local.logs_enabled || local.service_logs_enabled || local.application_enabled)
  workspace_enabled = local.agent_required || (local.enabled && local.synthetics_enabled)

  log_directory = "/var/log/oilscope"

  service_logs_by_role = {
    ui       = ["ui", "traefik", "redis"]
    history  = ["history", "rabbitmq"]
    fetcher  = ["fetcher"]
    database = ["postgres"]
  }

  monitored_roles = toset([
    for name in keys(local.workload_vms) : var.config.vms[name].role
  ])

  role_log_sources = {
    for role in local.monitored_roles : role => merge(
      local.logs_enabled && role == "ui" ? { access = ["${local.log_directory}/traefik-access.log"] } : {},
      local.service_logs_enabled ? { service = [
        for service in lookup(local.service_logs_by_role, role, []) : "${local.log_directory}/docker-${service}.log"
      ] } : {},
      local.application_enabled ? { metrics = ["${local.log_directory}/application-metrics.jsonl"] } : {},
    )
  }

  custom_streams = {
    access = {
      table  = "OilscopeAccess_CL"
      format = "json"
      stream_columns = [
        { name = "StartUTC", type = "string" },
        { name = "DownstreamStatus", type = "int" },
        { name = "RequestMethod", type = "string" },
        { name = "RequestPath", type = "string" },
        { name = "Duration", type = "long" },
        { name = "ClientHost", type = "string" },
        { name = "RouterName", type = "string" },
        { name = "ServiceName", type = "string" },
      ]
      table_columns = [
        { name = "TimeGenerated", type = "dateTime" },
        { name = "DownstreamStatus", type = "int" },
        { name = "RequestMethod", type = "string" },
        { name = "RequestPath", type = "string" },
        { name = "Duration", type = "long" },
        { name = "ClientHost", type = "string" },
        { name = "RouterName", type = "string" },
        { name = "ServiceName", type = "string" },
      ]
      transform = "source | extend TimeGenerated = todatetime(StartUTC) | project-away StartUTC"
    }
    service = {
      table  = "OilscopeService_CL"
      format = "text"
      stream_columns = [
        { name = "TimeGenerated", type = "datetime" },
        { name = "RawData", type = "string" },
        { name = "FilePath", type = "string" },
        { name = "Computer", type = "string" },
      ]
      table_columns = [
        { name = "TimeGenerated", type = "dateTime" },
        { name = "RawData", type = "string" },
        { name = "FilePath", type = "string" },
        { name = "Computer", type = "string" },
      ]
      transform = "source"
    }
    metrics = {
      table  = "OilscopeMetrics_CL"
      format = "json"
      stream_columns = [
        { name = "Timestamp", type = "string" },
        { name = "VMKey", type = "string" },
        { name = "Role", type = "string" },
        { name = "Metric", type = "string" },
        { name = "Value", type = "real" },
      ]
      table_columns = [
        { name = "TimeGenerated", type = "dateTime" },
        { name = "VMKey", type = "string" },
        { name = "Role", type = "string" },
        { name = "Metric", type = "string" },
        { name = "Value", type = "real" },
      ]
      transform = "source | extend TimeGenerated = todatetime(Timestamp) | project-away Timestamp"
    }
  }

  active_streams = toset(flatten([for sources in values(local.role_log_sources) : keys(sources)]))

  guest_signals = {
    memory = { namespace = "Memory", metric = "% Used Memory", threshold = local.settings.memory_threshold_percent }
    disk   = { namespace = "LogicalDisk", metric = "% Used Space", threshold = local.settings.disk_threshold_percent }
  }

  database_signals = {
    cpu         = { metric = "cpu_percent", threshold = local.settings.database_cpu_threshold_percent }
    storage     = { metric = "storage_percent", threshold = local.settings.database_disk_threshold_percent }
    connections = { metric = "active_connections", threshold = local.settings.database_connections_threshold }
  }

  http_filters = {
    HTTP500Count = "DownstreamStatus == 500"
    HTTP5xxCount = "DownstreamStatus >= 500 and DownstreamStatus < 600"
  }
}
