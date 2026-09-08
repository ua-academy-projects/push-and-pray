data "google_project" "current" {
  project_id = var.project_id
}

resource "google_billing_budget" "project" {
  count = var.settings.budget.enabled ? 1 : 0

  billing_account = var.billing_account_id
  display_name    = "${var.resource_prefix} monthly budget"

  budget_filter {
    projects        = ["projects/${data.google_project.current.number}"]
    calendar_period = "MONTH"
  }

  amount {
    specified_amount {
      currency_code = var.settings.budget.currency
      units         = tostring(floor(var.settings.budget.amount))
      nanos         = floor((var.settings.budget.amount - floor(var.settings.budget.amount)) * 1000000000)
    }
  }

  dynamic "threshold_rules" {
    for_each = var.settings.budget.thresholds

    content {
      threshold_percent = threshold_rules.value
      spend_basis       = "CURRENT_SPEND"
    }
  }

  all_updates_rule {
    monitoring_notification_channels = local.notification_channels
    disable_default_iam_recipients   = false
  }

  lifecycle {
    precondition {
      condition     = var.billing_account_id != null && var.billing_account_id != ""
      error_message = "Budget monitoring is enabled, but clouds.gcp.billing_account_id is missing from project config."
    }
  }
}
