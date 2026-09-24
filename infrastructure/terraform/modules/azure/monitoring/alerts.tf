resource "azurerm_monitor_action_group" "alerts" {
  count = local.monitoring_enabled ? 1 : 0

  name                = "${local.resource_prefix}-alerts"
  resource_group_name = var.resource_group_names[local.alerts_location]
  short_name          = substr("${var.config.name_prefix}-alerts", 0, 12)
  tags                = local.labels

  email_receiver {
    name                    = "monitoring-email"
    email_address           = var.config.monitoring.alert_email
    use_common_alert_schema = true
  }
}

resource "azurerm_monitor_metric_alert" "platform" {
  for_each = local.platform_alerts

  name                = "${each.value.vm.name}-${each.value.suffix}"
  resource_group_name = var.resource_group_names[each.value.vm.location]
  scopes              = [each.value.vm.resource_id]
  description         = each.value.description
  severity            = each.value.severity
  frequency           = "PT1M"
  window_size         = "PT5M"
  auto_mitigate       = true
  tags                = local.labels

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = each.value.metric_name
    aggregation      = "Average"
    operator         = each.value.operator
    threshold        = each.value.threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.alerts[0].id
  }
}

resource "azurerm_user_assigned_identity" "alerts" {
  count = local.monitoring_enabled ? 1 : 0

  name                = "${local.resource_prefix}-id-monitoring-alerts"
  resource_group_name = var.resource_group_names[local.alerts_location]
  location            = local.locations[local.alerts_location].region
  tags                = local.labels
}

resource "azurerm_role_assignment" "alerts_metrics_reader" {
  for_each = local.locations

  scope                = azurerm_monitor_workspace.metrics[each.key].id
  role_definition_name = "Monitoring Reader"
  principal_id         = azurerm_user_assigned_identity.alerts[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azapi_resource" "filesystem_alert" {
  for_each = local.locations

  type      = "Microsoft.Insights/metricAlerts@2024-03-01-preview"
  name      = "${local.resource_prefix}-filesystem-high${local.location_suffixes[each.key]}"
  parent_id = split("/providers/", azurerm_monitor_workspace.metrics[each.key].id)[0]
  location  = each.value.region
  tags      = local.labels

  schema_validation_enabled = false

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.alerts[0].id]
  }

  body = {
    properties = {
      enabled              = true
      description          = "Linux root filesystem usage exceeds 85 percent for five minutes."
      severity             = 2
      scopes               = [azurerm_monitor_workspace.metrics[each.key].id]
      targetResourceType   = "Microsoft.Monitor/accounts"
      targetResourceRegion = each.value.region
      evaluationFrequency  = "PT1M"
      criteria = {
        "odata.type" = "Microsoft.Azure.Monitor.PromQLCriteria"
        failingPeriods = {
          "for" = "PT5M"
        }
        allOf = [{
          name          = "RootFilesystemUsage"
          criterionType = "StaticThresholdCriterion"
          query         = <<-PROMQL
            100 *
            sum by ("Microsoft.resourceid", device, mountpoint, type) (
              {"system.filesystem.usage", mountpoint="/", type=~"ext4|xfs|btrfs", state="used"}
            )
            /
            sum by ("Microsoft.resourceid", device, mountpoint, type) (
              {"system.filesystem.usage", mountpoint="/", type=~"ext4|xfs|btrfs"}
            ) > 85
          PROMQL
        }]
      }
      resolveConfiguration = {
        autoResolved  = true
        timeToResolve = "PT5M"
      }
      actions = [{
        actionGroupId = azurerm_monitor_action_group.alerts[0].id
      }]
    }
  }

  depends_on = [azurerm_role_assignment.alerts_metrics_reader]
}
