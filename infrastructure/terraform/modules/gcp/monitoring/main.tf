resource "google_monitoring_notification_channel" "email" {
  count = local.monitoring_enabled ? 1 : 0

  project      = var.config.clouds.gcp.project_id
  display_name = "${var.config.name_prefix}-${var.config.environment} monitoring email"
  type         = "email"

  labels = {
    email_address = var.config.monitoring.alert_email
  }

}

resource "google_monitoring_alert_policy" "instance_health" {
  for_each = var.vms

  project      = var.config.clouds.gcp.project_id
  display_name = "${each.value.name} instance health"
  combiner     = "OR"
  severity     = "CRITICAL"

  conditions {
    display_name = "${each.value.name} stopped reporting uptime"

    condition_absent {
      filter   = "metric.type=\"compute.googleapis.com/instance/uptime\" AND resource.type=\"gce_instance\" AND resource.labels.instance_id=\"${each.value.id}\""
      duration = "300s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MAX"
      }
    }
  }

  notification_channels = google_monitoring_notification_channel.email[*].name
}

resource "google_monitoring_alert_policy" "cpu" {
  for_each = var.vms

  project      = var.config.clouds.gcp.project_id
  display_name = "${each.value.name} high CPU"
  combiner     = "OR"
  severity     = "WARNING"

  conditions {
    display_name = "${each.value.name} CPU at or above 80 percent"

    condition_threshold {
      filter                  = "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" AND resource.type=\"gce_instance\" AND resource.labels.instance_id=\"${each.value.id}\""
      duration                = "300s"
      comparison              = "COMPARISON_GE"
      threshold_value         = 0.8
      evaluation_missing_data = "EVALUATION_MISSING_DATA_INACTIVE"

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = google_monitoring_notification_channel.email[*].name
}

resource "google_monitoring_alert_policy" "filesystem" {
  for_each = var.vms

  project      = var.config.clouds.gcp.project_id
  display_name = "${each.value.name} filesystem high"
  combiner     = "OR"
  severity     = "WARNING"

  conditions {
    display_name = "${each.value.name} filesystem at or above 85 percent"

    condition_threshold {
      filter                  = "metric.type=\"agent.googleapis.com/disk/percent_used\" AND metric.labels.state=\"used\" AND resource.type=\"gce_instance\" AND resource.labels.instance_id=\"${each.value.id}\""
      duration                = "300s"
      comparison              = "COMPARISON_GE"
      threshold_value         = 85
      evaluation_missing_data = "EVALUATION_MISSING_DATA_INACTIVE"

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_MEAN"
        cross_series_reducer = "REDUCE_MAX"
        group_by_fields      = ["resource.label.instance_id"]
      }
    }
  }

  notification_channels = google_monitoring_notification_channel.email[*].name
}

resource "google_monitoring_dashboard" "health" {
  count = local.monitoring_enabled ? 1 : 0

  project = var.config.clouds.gcp.project_id
  dashboard_json = jsonencode({
    displayName = "${var.config.name_prefix}-${var.config.environment}-health"
    gridLayout = {
      columns = "2"
      widgets = [
        {
          title = "Instance uptime"
          xyChart = {
            dataSets = [
              for name, vm in var.vms : {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"compute.googleapis.com/instance/uptime\" AND resource.type=\"gce_instance\" AND resource.labels.instance_id=\"${vm.id}\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_MAX"
                    }
                  }
                }
                plotType       = "LINE"
                legendTemplate = vm.name
              }
            ]
            yAxis = {
              label = "seconds"
              scale = "LINEAR"
            }
          }
        },
      ]
    }
  })
}

resource "google_monitoring_dashboard" "cpu" {
  count = local.monitoring_enabled ? 1 : 0

  project = var.config.clouds.gcp.project_id
  dashboard_json = jsonencode({
    displayName = "${var.config.name_prefix}-${var.config.environment}-cpu"
    gridLayout = {
      columns = "2"
      widgets = [
        {
          title = "CPU utilization"
          xyChart = {
            dataSets = [
              for name, vm in var.vms : {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" AND resource.type=\"gce_instance\" AND resource.labels.instance_id=\"${vm.id}\""
                    aggregation = {
                      alignmentPeriod  = "300s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
                plotType       = "LINE"
                legendTemplate = vm.name
              }
            ]
            thresholds = [
              {
                label      = "Alert threshold (80%)"
                targetAxis = "Y1"
                value      = 0.8
              },
            ]
            yAxis = {
              label = "utilization"
              scale = "LINEAR"
            }
          }
        },
      ]
    }
  })
}

resource "google_monitoring_dashboard" "filesystem" {
  count = local.monitoring_enabled ? 1 : 0

  project = var.config.clouds.gcp.project_id
  dashboard_json = jsonencode({
    displayName = "${var.config.name_prefix}-${var.config.environment}-filesystem"
    gridLayout = {
      columns = "2"
      widgets = [
        {
          title = "Filesystem utilization"
          xyChart = {
            dataSets = [
              for name, vm in var.vms : {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"agent.googleapis.com/disk/percent_used\" AND metric.labels.state=\"used\" AND resource.type=\"gce_instance\" AND resource.labels.instance_id=\"${vm.id}\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_MEAN"
                      crossSeriesReducer = "REDUCE_MAX"
                      groupByFields      = ["resource.label.instance_id"]
                    }
                  }
                }
                plotType       = "LINE"
                legendTemplate = vm.name
              }
            ]
            thresholds = [
              {
                label      = "Alert threshold (85%)"
                targetAxis = "Y1"
                value      = 85
              },
            ]
            yAxis = {
              label = "percent"
              scale = "LINEAR"
            }
          }
        },
      ]
    }
  })
}

resource "google_monitoring_dashboard" "budget" {
  count = local.monitoring_enabled && local.budget_enabled ? 1 : 0

  project = var.config.clouds.gcp.project_id
  dashboard_json = jsonencode({
    displayName = "${var.config.name_prefix}-${var.config.environment}-budget"
    gridLayout = {
      columns = "2"
      widgets = [
        {
          title = "Monthly GCP budget"
          text = {
            content = <<-EOT
              ## Configured monthly budget

              - Limit: **${var.config.monitoring.monthly_budget.amount} ${var.config.monitoring.monthly_budget.currency}**
              - Actual-spend notification threshold: **80%**
              - Forecast-spend notification threshold: **100%**
              - Billing account: `${var.config.monitoring.monthly_budget.gcp_billing_account_id}`
              - Project: `${var.config.clouds.gcp.project_id}`

              Live spend remains available in **Google Cloud Console → Billing → Reports / Budgets & alerts**.
            EOT
            format  = "MARKDOWN"
          }
        },
      ]
    }
  })
}

data "google_project" "monitored" {
  count = local.monitoring_enabled && local.budget_enabled ? 1 : 0

  project_id = var.config.clouds.gcp.project_id
}

resource "google_billing_budget" "monthly" {
  count = local.monitoring_enabled && local.budget_enabled ? 1 : 0

  billing_account = "billingAccounts/${var.config.monitoring.monthly_budget.gcp_billing_account_id}"
  display_name    = "${var.config.name_prefix}-${var.config.environment} monthly"

  budget_filter {
    projects = ["projects/${data.google_project.monitored[0].number}"]
  }

  amount {
    specified_amount {
      currency_code = var.config.monitoring.monthly_budget.currency
      units         = tostring(var.config.monitoring.monthly_budget.amount)
    }
  }

  threshold_rules {
    threshold_percent = 0.8
  }

  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "FORECASTED_SPEND"
  }

  all_updates_rule {
    monitoring_notification_channels = google_monitoring_notification_channel.email[*].name
    disable_default_iam_recipients   = true
  }

}
