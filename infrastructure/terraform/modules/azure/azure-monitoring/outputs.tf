output "log_analytics_workspace_id" {
  description = "Primary Log Analytics workspace ID, or null when Azure monitoring is disabled."
  value       = try(azurerm_log_analytics_workspace.this[0].id, null)
}

output "log_analytics_workspace_ids" {
  description = "Log Analytics workspace IDs keyed by Azure location."
  value = merge(
    try({ (var.location) = azurerm_log_analytics_workspace.this[0].id }, {}),
    { for location, workspace in azurerm_log_analytics_workspace.regional : location => workspace.id },
  )
}

output "action_group_id" {
  description = "Azure Monitor email action group ID, or null when disabled."
  value       = try(azurerm_monitor_action_group.email[0].id, null)
}

output "dashboard_id" {
  description = "Azure Portal dashboard ID, or null when disabled."
  value       = try(azurerm_portal_dashboard.infrastructure[0].id, null)
}

output "availability_test_id" {
  description = "Application Insights HTTPS test ID, or null when disabled."
  value       = try(azurerm_application_insights_standard_web_test.https[0].id, null)
}
