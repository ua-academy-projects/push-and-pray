resource "google_monitoring_notification_channel" "email" {
  project      = var.project_id
  display_name = "${var.resource_prefix} alerts"
  type         = "email"
  labels       = { email_address = var.email }
}

# One policy per watched metric, over every VM the filter selects. A policy
# with a threshold fires when a VM crosses it for five minutes; the one
# without fires when a VM's series stops, which is what "down" looks like.
resource "google_monitoring_alert_policy" "metric" {
  for_each = var.metrics

  project               = var.project_id
  display_name          = "${var.resource_prefix}: ${each.value.title}"
  combiner              = "OR"
  notification_channels = [google_monitoring_notification_channel.email.id]

  conditions {
    display_name = each.value.threshold == null ? "${each.value.title} missing" : "${each.value.title} above ${each.value.threshold}"

    dynamic "condition_threshold" {
      for_each = each.value.threshold == null ? [] : [each.value.threshold]

      content {
        filter          = each.value.filter
        comparison      = "COMPARISON_GT"
        threshold_value = condition_threshold.value
        duration        = "300s"

        aggregations {
          alignment_period   = "60s"
          per_series_aligner = each.value.aligner
        }
      }
    }

    dynamic "condition_absent" {
      for_each = each.value.threshold == null ? [1] : []

      content {
        filter   = each.value.filter
        duration = "300s"

        aggregations {
          alignment_period   = "60s"
          per_series_aligner = each.value.aligner
        }
      }
    }
  }

  documentation {
    subject = "${var.resource_prefix}: ${each.value.title} on instance $${resource.label.instance_id}"
    content = each.value.threshold == null ? "No ${lower(each.value.title)} reported for five minutes: the VM is down or unreachable." : "${each.value.title} stayed above ${each.value.threshold} for five minutes."
  }

  alert_strategy {
    auto_close = "1800s"
  }
}

data "google_project" "this" {
  project_id = var.project_id
}

resource "google_project_service" "billingbudgets" {
  count = var.budget_usd != null && var.billing_account != null ? 1 : 0

  project            = var.project_id
  service            = "billingbudgets.googleapis.com"
  disable_on_destroy = false
}

resource "google_billing_budget" "monthly" {
  count = var.budget_usd != null && var.billing_account != null ? 1 : 0

  billing_account = var.billing_account
  display_name    = "${var.resource_prefix} monthly"

  budget_filter {
    projects        = ["projects/${data.google_project.this.number}"]
    calendar_period = "MONTH"
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(floor(var.budget_usd))
    }
  }

  threshold_rules {
    threshold_percent = 1.0
  }

  all_updates_rule {
    monitoring_notification_channels = [google_monitoring_notification_channel.email.id]
    disable_default_iam_recipients   = true
  }

  depends_on = [google_project_service.billingbudgets]
}
