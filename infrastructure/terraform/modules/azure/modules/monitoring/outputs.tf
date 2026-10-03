output "metrics" {
  description = "The watched platform metrics - name, aggregation, operator and threshold - for alerting to build one rule per VM and entry."
  value       = local.metrics
}

output "memory_threshold_mb" {
  description = "Memory in use above which the memory alert fires, in the MB the agent's counter reports."
  value       = var.thresholds.memory_used_gb * 1024
}

output "window_minutes" {
  description = "Length of the window every alert evaluates, which the totals above are scaled to."
  value       = local.window_minutes
}

output "dashboard_id" {
  description = "ID of the dashboard."
  value       = azurerm_portal_dashboard.hosts.id
}
