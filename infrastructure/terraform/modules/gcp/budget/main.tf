# This API owner remains independent of workload monitoring enablement.
resource "google_project_service" "budgets" {
  for_each           = var.settings.enabled ? toset(["billingbudgets.googleapis.com"]) : toset([])
  project            = var.project_id
  service            = each.key
  disable_on_destroy = false
}
data "google_project" "budget" {
  count      = var.settings.enabled ? 1 : 0
  project_id = var.project_id
}
data "google_billing_account" "budget" {
  count           = var.settings.enabled ? 1 : 0
  billing_account = var.settings.billing_account_id
  lookup_projects = false
}
resource "google_monitoring_notification_channel" "budget" {
  for_each     = var.settings.enabled ? var.settings.email_recipients : toset([])
  project      = var.project_id
  display_name = "${var.name} budget ${each.key}"
  type         = "email"
  labels       = { email_address = each.key }
}
resource "google_billing_budget" "monthly" {
  count           = var.settings.enabled ? 1 : 0
  billing_account = var.settings.billing_account_id
  display_name    = var.name
  budget_filter {
    projects               = ["projects/${data.google_project.budget[0].number}"]
    calendar_period        = "MONTH"
    credit_types_treatment = "INCLUDE_ALL_CREDITS"
  }
  amount {
    specified_amount {
      currency_code = var.settings.currency
      units         = tostring(var.settings.monthly_amount)
    }
  }
  # GCP billing budgets only support percent-of-budget thresholds (no
  # absolute-value option like AWS), so convert each configured currency
  # amount into the fraction of this budget's own monthly_amount it represents.
  dynamic "threshold_rules" {
    for_each = var.settings.actual_thresholds
    content {
      threshold_percent = threshold_rules.value / var.settings.monthly_amount
      spend_basis       = "CURRENT_SPEND"
    }
  }
  all_updates_rule {
    monitoring_notification_channels = [for channel in google_monitoring_notification_channel.budget : channel.name]
    disable_default_iam_recipients   = true
  }
  lifecycle {
    precondition {
      condition     = var.settings.currency == data.google_billing_account.budget[0].currency_code
      error_message = "Budget currency must match the GCP billing account currency."
    }
  }
  depends_on = [google_project_service.budgets]
}
output "summary" {
  value = var.settings.enabled ? { id = google_billing_budget.monthly[0].id, scope = "GCP project ${var.project_id}", amount = var.settings.monthly_amount, currency = var.settings.currency, thresholds = var.settings.actual_thresholds } : null
}
