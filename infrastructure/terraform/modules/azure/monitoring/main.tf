resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.resource_prefix}-logs"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_monitor_action_group" "alarms" {
  name                = "${var.resource_prefix}-alarms"
  resource_group_name = var.resource_group_name
  short_name          = substr(replace(var.resource_prefix, "-", ""), 0, 12)
  tags                = var.tags

  email_receiver {
    name          = "operator"
    email_address = var.settings.notification_email
  }
}

resource "azurerm_monitor_metric_alert" "high_cpu" {
  for_each = var.virtual_machine_ids

  name                = "${var.resource_prefix}-${each.key}-high-cpu"
  resource_group_name = var.resource_group_name
  scopes              = [each.value]
  description         = "Azure VM CPU utilization exceeded the configured threshold."
  severity            = 2
  frequency           = "PT1M"
  window_size         = local.cpu_window
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.settings.cpu.threshold_percent
  }

  action {
    action_group_id = azurerm_monitor_action_group.alarms.id
  }
}

resource "azurerm_monitor_metric_alert" "vm_unavailable" {
  for_each = var.virtual_machine_ids

  name                = "${var.resource_prefix}-${each.key}-vm-unavailable"
  resource_group_name = var.resource_group_name
  scopes              = [each.value]
  description         = "Azure VM availability dropped below 100 percent."
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = var.tags

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "VmAvailabilityMetric"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 1
  }

  action {
    action_group_id = azurerm_monitor_action_group.alarms.id
  }
}

resource "azurerm_monitor_data_collection_rule" "linux" {
  count = var.settings.logs.enabled ? 1 : 0

  name                = "${var.resource_prefix}-linux"
  resource_group_name = var.resource_group_name
  location            = var.location
  kind                = "Linux"
  tags                = var.tags

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.main.id
      name                  = "workspace"
    }
  }

  data_sources {
    performance_counter {
      name                          = "linux-performance"
      streams                       = ["Microsoft-Perf"]
      sampling_frequency_in_seconds = 60
      counter_specifiers = [
        "\\Processor Information(_Total)\\% Processor Time",
        "\\Logical Disk(*)\\% Used Space",
      ]
    }

    syslog {
      name           = "linux-syslog"
      facility_names = ["*"]
      log_levels     = ["*"]
      streams        = ["Microsoft-Syslog"]
    }
  }

  data_flow {
    streams      = ["Microsoft-Perf", "Microsoft-Syslog"]
    destinations = ["workspace"]
  }
}

resource "azurerm_virtual_machine_extension" "monitor_agent" {
  for_each = var.settings.logs.enabled ? var.virtual_machine_ids : {}

  name                       = "AzureMonitorLinuxAgent"
  virtual_machine_id         = each.value
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorLinuxAgent"
  type_handler_version       = "1.0"
  automatic_upgrade_enabled  = true
  auto_upgrade_minor_version = true
  tags                       = var.tags
}

resource "azurerm_monitor_data_collection_rule_association" "linux" {
  for_each = var.settings.logs.enabled ? var.virtual_machine_ids : {}

  name                    = "${var.resource_prefix}-${each.key}-linux"
  target_resource_id      = each.value
  data_collection_rule_id = azurerm_monitor_data_collection_rule.linux[0].id

  depends_on = [azurerm_virtual_machine_extension.monitor_agent]
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "high_disk" {
  count = var.settings.logs.enabled ? 1 : 0

  name                  = "${var.resource_prefix}-high-disk"
  resource_group_name   = var.resource_group_name
  location              = var.location
  evaluation_frequency  = "PT5M"
  window_duration       = local.disk_window
  scopes                = [azurerm_log_analytics_workspace.main.id]
  severity              = 2
  description           = "A Linux VM filesystem exceeded the configured disk usage threshold."
  skip_query_validation = true
  tags                  = var.tags

  criteria {
    query                   = <<-QUERY
      Perf
      | where ObjectName == "Logical Disk" and CounterName == "% Used Space" and InstanceName != "_Total"
      | summarize AggregatedValue=max(CounterValue) by _ResourceId, bin(TimeGenerated, 5m)
    QUERY
    time_aggregation_method = "Maximum"
    metric_measure_column   = "AggregatedValue"
    resource_id_column      = "_ResourceId"
    operator                = "GreaterThan"
    threshold               = var.settings.disk.threshold_percent

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.alarms.id]
  }

  depends_on = [azurerm_monitor_data_collection_rule_association.linux]
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "application_errors" {
  count = var.settings.logs.enabled ? 1 : 0

  name                  = "${var.resource_prefix}-application-errors"
  resource_group_name   = var.resource_group_name
  location              = var.location
  evaluation_frequency  = "PT5M"
  window_duration       = "PT5M"
  scopes                = [azurerm_log_analytics_workspace.main.id]
  severity              = 2
  description           = "A Linux workload emitted a syslog message matching the configured error pattern."
  skip_query_validation = true
  tags                  = var.tags

  criteria {
    query                   = <<-QUERY
      Syslog
      | where SyslogMessage matches regex @"${replace(var.settings.logs.error_pattern, "\"", "\"\"")}"
    QUERY
    time_aggregation_method = "Count"
    operator                = "GreaterThan"
    threshold               = 0

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.alarms.id]
  }

  depends_on = [azurerm_monitor_data_collection_rule_association.linux]
}

resource "azurerm_application_insights" "uptime" {
  count = var.settings.uptime.enabled ? 1 : 0

  name                = "${var.resource_prefix}-uptime"
  location            = var.location
  resource_group_name = var.resource_group_name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  tags                = var.tags
}

resource "azurerm_application_insights_standard_web_test" "ui" {
  count = var.settings.uptime.enabled ? 1 : 0

  name                    = "${var.resource_prefix}-ui"
  resource_group_name     = var.resource_group_name
  location                = var.location
  application_insights_id = azurerm_application_insights.uptime[0].id
  geo_locations           = ["emea-nl-ams-azr", "emea-gb-db3-azr"]
  frequency               = max(300, var.settings.uptime.period_seconds)
  timeout                 = var.settings.uptime.timeout_seconds
  retry_enabled           = true
  tags                    = var.tags

  request {
    url = "https://${var.uptime_hostname}${var.settings.uptime.path}"
  }

  validation_rules {
    ssl_check_enabled = true
  }

  lifecycle {
    precondition {
      condition     = var.uptime_hostname != null && var.uptime_hostname != ""
      error_message = "Uptime monitoring is enabled, but no Azure UI hostname was found."
    }
  }
}

resource "azurerm_monitor_metric_alert" "ui_unavailable" {
  count = var.settings.uptime.enabled ? 1 : 0

  name                = "${var.resource_prefix}-ui-http-unavailable"
  resource_group_name = var.resource_group_name
  scopes = [
    azurerm_application_insights_standard_web_test.ui[0].id,
    azurerm_application_insights.uptime[0].id,
  ]
  description = "The public UI HTTPS availability test failed."
  severity    = 1
  tags        = var.tags

  application_insights_web_test_location_availability_criteria {
    web_test_id           = azurerm_application_insights_standard_web_test.ui[0].id
    component_id          = azurerm_application_insights.uptime[0].id
    failed_location_count = 2
  }

  action {
    action_group_id = azurerm_monitor_action_group.alarms.id
  }
}

resource "azurerm_consumption_budget_resource_group" "monthly" {
  count = var.settings.budget.enabled ? 1 : 0

  name              = "${var.resource_prefix}-monthly"
  resource_group_id = var.resource_group_id
  amount            = var.settings.budget.amount
  time_grain        = "Monthly"

  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00'Z'", timestamp())
    end_date   = formatdate("YYYY-MM-01'T'00:00:00'Z'", timeadd(timestamp(), "87600h"))
  }

  dynamic "notification" {
    for_each = var.settings.budget.thresholds

    content {
      enabled        = true
      threshold      = notification.value * 100
      operator       = "GreaterThan"
      threshold_type = "Actual"
      contact_emails = [var.settings.notification_email]
      contact_groups = [azurerm_monitor_action_group.alarms.id]
    }
  }

  lifecycle {
    ignore_changes = [time_period]
  }
}
