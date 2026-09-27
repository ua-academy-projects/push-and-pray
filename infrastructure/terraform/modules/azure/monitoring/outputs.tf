output "summary" {
  value = {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
    action_group_id            = azurerm_monitor_action_group.alarms.id
    cpu_alert_ids              = { for name, alert in azurerm_monitor_metric_alert.high_cpu : name => alert.id }
    availability_alert_ids     = { for name, alert in azurerm_monitor_metric_alert.vm_unavailable : name => alert.id }
    disk_alert_id              = try(azurerm_monitor_scheduled_query_rules_alert_v2.high_disk[0].id, null)
    application_error_alert_id = try(azurerm_monitor_scheduled_query_rules_alert_v2.application_errors[0].id, null)
    uptime_test_id             = try(azurerm_application_insights_standard_web_test.ui[0].id, null)
    uptime_alert_id            = try(azurerm_monitor_metric_alert.ui_unavailable[0].id, null)
    budget_id                  = try(azurerm_consumption_budget_resource_group.monthly[0].id, null)
  }
}
