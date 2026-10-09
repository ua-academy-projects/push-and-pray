output "log_analytics_workspace_id" {
  description = "Azure Log Analytics workspace resource ID."
  value       = try(azurerm_log_analytics_workspace.this["main"].id, null)
}

output "application_insights_id" {
  description = "Azure Application Insights component resource ID."
  value       = try(azurerm_application_insights.this["main"].id, null)
}

output "action_group_id" {
  description = "Azure Monitor Action Group resource ID, when email notifications are configured."
  value       = try(azurerm_monitor_action_group.this["main"].id, null)
}

output "workbook_id" {
  description = "Azure Monitor workbook resource ID."
  value       = try(azurerm_application_insights_workbook.this["main"].id, null)
}
