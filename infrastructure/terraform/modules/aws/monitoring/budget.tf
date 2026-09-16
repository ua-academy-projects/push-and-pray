resource "aws_budgets_budget" "monthly" {
  count = var.settings.budget.enabled ? 1 : 0

  name         = "${var.resource_prefix}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.settings.budget.amount)
  limit_unit   = var.settings.budget.currency
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = var.settings.budget.thresholds

    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value * 100
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = [var.settings.notification_email]
    }
  }
}
