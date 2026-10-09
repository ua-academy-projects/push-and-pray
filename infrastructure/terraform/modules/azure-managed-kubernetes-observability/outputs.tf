output "workbook_id" {
  description = "Azure Monitor workbook resource ID for the AKS cluster."
  value       = azurerm_application_insights_workbook.this.id
}

output "container_insights_data_collection_rule_id" {
  description = "Data collection rule supplying AKS Container Insights logs and performance data."
  value       = azurerm_monitor_data_collection_rule.container_insights.id
}

output "web_test_id" {
  description = "Application Insights HTTPS availability test resource ID."
  value       = azurerm_application_insights_standard_web_test.https.id
}
