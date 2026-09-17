resource "aws_budgets_budget" "monthly" {
  count        = var.settings.enabled ? 1 : 0
  name         = var.name
  budget_type  = "COST"
  limit_amount = tostring(var.settings.monthly_amount)
  limit_unit   = var.settings.currency
  time_unit    = "MONTHLY"
  cost_types {
    include_credit = true
    include_refund = true
    include_tax    = true
    use_blended    = false
  }
  dynamic "notification" {
    for_each = var.settings.actual_thresholds
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "ABSOLUTE_VALUE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = var.settings.email_recipients
    }
  }
}
output "summary" {
  value = var.settings.enabled ? { id = aws_budgets_budget.monthly[0].id, scope = "AWS account (all services)", amount = var.settings.monthly_amount, currency = var.settings.currency, thresholds = var.settings.actual_thresholds } : null
}
