resource "azurerm_monitor_action_group" "alerts" {
  count = var.has_selected_vms ? 1 : 0

  name                = "${local.resource_prefix}-alerts"
  resource_group_name = var.resource_group_name
  short_name          = var.config.name_prefix

  email_receiver {
    name          = "operator"
    email_address = var.config.monitoring.notification_email
  }
}

resource "azurerm_monitor_metric_alert" "cpu_high" {
  for_each = local.selected_vms

  name                = "${local.resource_prefix}-${each.key}-cpu-high"
  resource_group_name = var.resource_group_name
  scopes              = [var.instance_ids[each.key]]

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = try(var.config.monitoring.cpu_threshold_percent, 80)
  }

  action {
    action_group_id = azurerm_monitor_action_group.alerts[0].id
  }
}

resource "azurerm_consumption_budget_resource_group" "main" {
  count = var.has_selected_vms ? 1 : 0

  name              = "${local.resource_prefix}-budget"
  resource_group_id = var.resource_group_id
  amount            = var.config.monitoring.budget_amount_usd
  time_grain        = "Monthly"

  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00Z", timestamp())
  }

  lifecycle {
    ignore_changes = [time_period]
  }

  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = [var.config.monitoring.notification_email]
  }
}