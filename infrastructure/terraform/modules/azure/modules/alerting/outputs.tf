output "action_group_id" {
  description = "The action group every alert notifies."
  value       = azurerm_monitor_action_group.alerts.id
}
