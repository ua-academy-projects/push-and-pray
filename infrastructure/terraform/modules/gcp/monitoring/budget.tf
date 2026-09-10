data "google_project" "current" {
  count = var.has_selected_vms ? 1 : 0
}

resource "google_billing_budget" "main" {
    count = var.has_selected_vms ? 1 : 0

    billing_account = try(var.config.monitoring.gcp_billing_account_id, null)
    display_name    = "${local.resource_prefix}-budget"

    budget_filter {
        projects = ["projects/${data.google_project.current[0].number}"]
    }

    amount {
        specified_amount {
            currency_code = "USD"
            units = tostring(var.config.monitoring.budget_amount_usd)
        }
    }

    all_updates_rule {
        monitoring_notification_channels = [google_monitoring_notification_channel.email[0].id]
        disable_default_iam_recipients = false
    }

}