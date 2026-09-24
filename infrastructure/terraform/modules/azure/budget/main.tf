resource "azurerm_consumption_budget_resource_group" "monthly" {
  count             = var.settings.enabled ? 1 : 0
  name              = var.name
  resource_group_id = var.resource_group_id

  amount     = var.settings.monthly_amount
  time_grain = "Monthly"

  time_period {
    start_date = var.settings.start_date
  }

  dynamic "notification" {
    for_each = var.settings.actual_thresholds
    content {
      enabled        = true
      threshold      = 100 * notification.value / var.settings.monthly_amount
      threshold_type = "Actual"
      operator       = "GreaterThanOrEqualTo"
      contact_emails = var.settings.email_recipients
    }
  }
}
output "summary" {
  value = var.settings.enabled ? { id = azurerm_consumption_budget_resource_group.monthly[0].id, scope = "Azure resource group ${var.name}", amount = var.settings.monthly_amount, currency = var.settings.currency, thresholds = var.settings.actual_thresholds } : null
}
