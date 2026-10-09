resource "azurerm_monitor_action_group" "alerts" {
  name                = "${var.resource_prefix}-alerts"
  resource_group_name = var.resource_group_name
  # What an SMS or a push notification is signed with; twelve characters at
  # most.
  short_name = substr(var.resource_prefix, 0, 12)

  email_receiver {
    name                    = "operator"
    email_address           = var.email
    use_common_alert_schema = true
  }

  tags = var.tags
}

# One rule per VM and watched metric, as on AWS. A rule may list several VMs,
# but only for some metrics - Network In Total, for one, takes a single
# resource - so every rule watches one VM rather than splitting the table.
resource "azurerm_monitor_metric_alert" "metric" {
  for_each = {
    for pair in setproduct(keys(var.instances), keys(var.metrics)) :
    "${pair[0]}/${pair[1]}" => { instance = var.instances[pair[0]], key = pair[1], metric = var.metrics[pair[1]] }
  }

  name                = "${each.value.instance.name}-${replace(each.value.key, "_", "-")}"
  resource_group_name = var.resource_group_name
  description         = "${each.value.instance.name}: ${each.value.metric.title} ${each.value.metric.operator} ${each.value.metric.threshold}"
  scopes              = [each.value.instance.id]
  frequency           = "PT1M"
  window_size         = "PT${var.window_minutes}M"
  severity            = 2

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = each.value.metric.name
    aggregation      = each.value.metric.aggregation
    operator         = each.value.metric.operator
    threshold        = each.value.metric.threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.alerts.id
  }

  tags = var.tags
}

# A stopped or deallocated VM reports no metric at all, and a metric alert
# ignores silence - where AWS treats missing data as breaching and GCP alerts
# on an absent series. Resource health does report it.
resource "azurerm_monitor_activity_log_alert" "health" {
  name                = "${var.resource_prefix}-vm-health"
  resource_group_name = var.resource_group_name
  location            = "global"
  scopes              = [var.resource_group_id]
  description         = "A VM of ${var.resource_prefix} became unavailable or degraded"

  criteria {
    category      = "ResourceHealth"
    resource_type = "Microsoft.Compute/virtualMachines"

    resource_health {
      current = ["Unavailable", "Degraded"]
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.alerts.id
  }

  tags = var.tags
}

# The log-based alerts query the workspace in KQL, and run as an identity of
# their own: without one, Azure checks the workspace with the credentials of
# whoever creates the rule, and that check fails about half the time with
# "insufficient access" even for the subscription owner. The identity needs
# read access to the workspace to run its query. The rule creates the identity
# itself: a user-assigned one, granted that access beforehand, was refused in
# every attempt.
#
# What reaches the workspace is syslog from rsyslog, so a journal entry
# arrives as SyslogMessage, tagged with its SYSLOG_IDENTIFIER in ProcessName,
# from the host in Computer - the VM name.

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "memory" {
  name                  = "${var.resource_prefix}-memory"
  resource_group_name   = var.resource_group_name
  location              = var.location
  description           = "Memory in use above ${var.memory_threshold_mb} MB"
  scopes                = [var.workspace_id]
  evaluation_frequency  = "PT5M"
  window_duration       = "PT${var.window_minutes}M"
  severity              = 2
  skip_query_validation = true

  identity {
    type = "SystemAssigned"
  }

  criteria {
    query                   = <<-KQL
      Perf
      | where ObjectName == "Memory" and CounterName == "Used Memory MBytes"
    KQL
    time_aggregation_method = "Average"
    metric_measure_column   = "CounterValue"
    operator                = "GreaterThan"
    threshold               = var.memory_threshold_mb

    dimension {
      name     = "Computer"
      operator = "Include"
      values   = ["*"]
    }

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.alerts.id]
  }

  tags = var.tags
}

# Scoped to the environment's resource group, which holds everything it
# spends on. Budgets mail the address directly; no action group in between.
resource "azurerm_consumption_budget_resource_group" "monthly" {
  count = var.budget_usd != null ? 1 : 0

  name              = "${var.resource_prefix}-monthly"
  resource_group_id = var.resource_group_id
  amount            = var.budget_usd
  time_grain        = "Monthly"

  # A budget must start on the first of a month; any month is as good as the
  # next, so the one it was created in is kept.
  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00Z", plantimestamp())
  }

  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = [var.email]
  }

  lifecycle {
    ignore_changes = [time_period]
  }
}

resource "azurerm_role_assignment" "log_rule_reader" {
  for_each = {
    memory = azurerm_monitor_scheduled_query_rules_alert_v2.memory.identity[0].principal_id
  }

  scope                = var.workspace_id
  role_definition_name = "Log Analytics Reader"
  principal_id         = each.value
  principal_type       = "ServicePrincipal"
}
