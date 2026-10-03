output "workspace_id" {
  description = "Resource ID of the Log Analytics workspace. The log-based alerts query it."
  value       = azurerm_log_analytics_workspace.main.id
}

output "workspace_name" {
  description = "Name of the workspace."
  value       = azurerm_log_analytics_workspace.main.name
}

output "data_collection_rule_id" {
  description = "ID of the rule that tells every agent what to collect."
  value       = azurerm_monitor_data_collection_rule.hosts.id
}
