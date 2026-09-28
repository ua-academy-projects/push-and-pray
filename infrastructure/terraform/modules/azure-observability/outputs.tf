output "log_analytics_workspace_id" {
  description = "Azure Log Analytics workspace resource ID."
  value       = try(azurerm_log_analytics_workspace.this["main"].id, null)
}

output "workbook_id" {
  description = "Azure Monitor workbook resource ID."
  value       = try(azurerm_application_insights_workbook.this["main"].id, null)
}
