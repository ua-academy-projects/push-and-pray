resource "aws_budgets_budget" "main" {
    count = var.has_selected_vms ? 1 : 0

    name        = "${local.resource_prefix}-budget"
    budget_type = "COST"
    limit_amount = tostring(var.config.monitoring.budget_amount_usd)
    limit_unit  = "USD"
    time_unit   = "MONTHLY"

    notification {
        comparison_operator       = "GREATER_THAN"
        threshold                 = 80
        threshold_type            = "PERCENTAGE"
        notification_type         = "ACTUAL"
        subscriber_email_addresses = [var.config.monitoring.notification_email]
    }
}