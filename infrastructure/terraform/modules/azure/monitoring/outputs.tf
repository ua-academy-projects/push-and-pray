output "workspace_id" {
  description = "Log Analytics workspace every signal is written to; null when disabled."
  value       = try(azurerm_log_analytics_workspace.main[0].id, null)
}
output "action_group_id" {
  description = "Operational alert action group; recipients receive mail without confirming a subscription."
  value       = try(azurerm_monitor_action_group.alerts[0].id, null)
}
output "workbook_id" {
  value = try(azurerm_application_insights_workbook.operations[0].id, null)
}
output "availability_test_id" {
  value = try(azurerm_application_insights_standard_web_test.health[0].id, null)
}
output "alert_ids" {
  value = merge(
    { for key, alert in azurerm_monitor_metric_alert.vm_cpu : "${key}-cpu" => alert.id },
    { for key, alert in azurerm_monitor_metric_alert.database : "database-${key}" => alert.id },
    { for key, alert in azurerm_monitor_scheduled_query_rules_alert_v2.logs : key => alert.id },
    { for key, alert in azurerm_monitor_metric_alert.health : "health" => alert.id },
  )
}
output "agent_configurations" {
  description = "Per-VM Azure Monitor Agent wiring. Unlike the AWS JSON and GCP YAML this is not a file to install: Terraform owns the extension and the rules, and deployment prepares the listed log sources and verifies the agent."
  value       = local.agent_configurations
}
