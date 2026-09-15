resource "google_project_iam_member" "ops_agent" {
  for_each = local.service_account_roles

  project = var.config.cloud_settings.gcp.project_id
  role    = each.value.role
  member  = "serviceAccount:${each.value.email}"
}

resource "google_logging_metric" "http_requests" {
  count = length(local.gcp_vms) == 0 ? 0 : 1

  project     = var.config.cloud_settings.gcp.project_id
  name        = "${local.resource_prefix}-http-requests"
  description = "Count of external HTTP requests handled by Traefik."
  filter      = "resource.type=\"gce_instance\" AND (${local.logging_instance_filter}) AND log_id(\"docker_json\") AND jsonPayload.log =~ \"RequestMethod\" AND NOT jsonPayload.log : \"/health\""

  metric_descriptor {
    display_name = "OilScope HTTP requests"
    metric_kind  = "DELTA"
    value_type   = "INT64"
    unit         = "1"
  }
}

resource "google_logging_metric" "http_5xx" {
  count = length(local.gcp_vms) == 0 ? 0 : 1

  project     = var.config.cloud_settings.gcp.project_id
  name        = "${local.resource_prefix}-http-5xx"
  description = "Count of HTTP 5xx responses returned by Traefik."
  filter      = "resource.type=\"gce_instance\" AND (${local.logging_instance_filter}) AND log_id(\"docker_json\") AND jsonPayload.log =~ \"DownstreamStatus[^0-9]*5[0-9]{2}[^0-9]\""

  metric_descriptor {
    display_name = "OilScope HTTP 5xx responses"
    metric_kind  = "DELTA"
    value_type   = "INT64"
    unit         = "1"
  }
}

resource "google_monitoring_alert_policy" "vm_metric" {
  for_each = length(local.gcp_vms) == 0 ? {} : local.vm_metric_alerts

  project      = var.config.cloud_settings.gcp.project_id
  display_name = each.value.display_name
  combiner     = "OR"
  severity     = "WARNING"

  conditions {
    display_name = each.value.condition_name

    condition_threshold {
      filter          = "resource.type=\"gce_instance\" AND ${each.value.metric_filter} AND (${local.monitoring_instance_filter})"
      comparison      = "COMPARISON_GT"
      threshold_value = each.value.threshold
      duration        = "900s"

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_MEAN"
        cross_series_reducer = each.value.cross_series_reducer
        group_by_fields      = each.value.group_by_fields
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = local.notification_channels

  alert_strategy {
    notification_prompts = ["OPENED", "CLOSED"]
  }
}

resource "google_monitoring_alert_policy" "vm_unavailable" {
  count = length(local.gcp_vms) == 0 ? 0 : 1

  project      = var.config.cloud_settings.gcp.project_id
  display_name = "${local.resource_prefix}-vm-unavailable"
  combiner     = "OR"
  severity     = "ERROR"

  conditions {
    display_name = "VM uptime metric absent for five minutes"

    condition_absent {
      filter   = "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/uptime\" AND (${local.monitoring_instance_filter})"
      duration = "300s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_SUM"
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = local.notification_channels

  alert_strategy {
    notification_prompts = ["OPENED", "CLOSED"]
  }
}

resource "google_monitoring_alert_policy" "http_5xx" {
  count = length(local.gcp_vms) == 0 ? 0 : 1

  project      = var.config.cloud_settings.gcp.project_id
  display_name = "${local.resource_prefix}-http-5xx"
  combiner     = "OR"
  severity     = "ERROR"

  conditions {
    display_name = "At least one HTTP 5xx response in five minutes"

    condition_matched_log {
      filter = google_logging_metric.http_5xx[0].filter
    }
  }

  notification_channels = local.notification_channels

  alert_strategy {
    auto_close           = "1800s"
    notification_prompts = ["OPENED", "CLOSED"]

    notification_rate_limit {
      period = "300s"
    }
  }
}

resource "google_monitoring_uptime_check_config" "https" {
  for_each = local.gcp_ui

  project            = var.config.cloud_settings.gcp.project_id
  display_name       = "${local.resource_prefix}-https-availability"
  timeout            = "10s"
  period             = "60s"
  checker_type       = "STATIC_IP_CHECKERS"
  log_check_failures = true

  http_check {
    path           = "/health"
    port           = 443
    request_method = "GET"
    use_ssl        = true
    validate_ssl   = true
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      host       = each.value.public_endpoint.hostname
      project_id = var.config.cloud_settings.gcp.project_id
    }
  }

  content_matchers {
    content = "\"status\":\"ok\""
    matcher = "CONTAINS_STRING"
  }

  user_labels = {
    application = var.config.name_prefix
    environment = var.config.environment
  }
}

resource "google_monitoring_alert_policy" "https_unavailable" {
  for_each = google_monitoring_uptime_check_config.https

  project      = var.config.cloud_settings.gcp.project_id
  display_name = "${local.resource_prefix}-https-unavailable"
  combiner     = "OR"
  severity     = "ERROR"

  conditions {
    display_name = "Most HTTPS probes fail for two minutes"

    condition_threshold {
      filter          = "resource.type=\"uptime_url\" AND metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND metric.label.check_id=\"${each.value.uptime_check_id}\""
      comparison      = "COMPARISON_LT"
      threshold_value = 0.5
      duration        = "120s"

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_FRACTION_TRUE"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields      = ["metric.label.check_id"]
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = local.notification_channels

  alert_strategy {
    notification_prompts = ["OPENED", "CLOSED"]
  }
}

resource "google_monitoring_dashboard" "this" {
  count = length(local.gcp_ui) == 0 ? 0 : 1

  project = var.config.cloud_settings.gcp.project_id
  dashboard_json = jsonencode({
    displayName = "Oilscope"
    labels = {
      managed_by = "terraform"
    }
    gridLayout = {
      columns = "2"
      widgets = [
        {
          title = "VM - CPU utilization"
          xyChart = {
            dataSets = [{
              plotType = "LINE"
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/cpu/utilization\" AND (${local.monitoring_instance_filter})"
                  aggregation = {
                    alignmentPeriod  = "300s"
                    perSeriesAligner = "ALIGN_MEAN"
                  }
                }
              }
            }]
            yAxis = { scale = "LINEAR" }
          }
        },
        {
          title = "VM - Memory utilization"
          xyChart = {
            dataSets = [{
              plotType = "LINE"
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"gce_instance\" AND metric.type=\"agent.googleapis.com/memory/percent_used\" AND metric.label.state=\"used\" AND (${local.monitoring_instance_filter})"
                  aggregation = {
                    alignmentPeriod  = "300s"
                    perSeriesAligner = "ALIGN_MEAN"
                  }
                }
              }
            }]
            yAxis = { scale = "LINEAR" }
          }
        },
        {
          title = "VM - Root disk utilization"
          xyChart = {
            dataSets = [{
              plotType = "LINE"
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"gce_instance\" AND metric.type=\"agent.googleapis.com/disk/percent_used\" AND metric.label.state=\"used\" AND metric.label.device=\"/dev/sda1\" AND (${local.monitoring_instance_filter})"
                  aggregation = {
                    alignmentPeriod  = "300s"
                    perSeriesAligner = "ALIGN_MEAN"
                  }
                }
              }
            }]
            yAxis = { scale = "LINEAR" }
          }
        },
        {
          title = "VM - Network traffic"
          xyChart = {
            dataSets = [
              {
                legendTemplate = "Received $${metric.labels.instance_name}"
                plotType       = "LINE"
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/network/received_bytes_count\" AND (${local.monitoring_instance_filter})"
                    aggregation = {
                      alignmentPeriod  = "300s"
                      perSeriesAligner = "ALIGN_RATE"
                    }
                  }
                }
              },
              {
                legendTemplate = "Sent $${metric.labels.instance_name}"
                plotType       = "LINE"
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/network/sent_bytes_count\" AND (${local.monitoring_instance_filter})"
                    aggregation = {
                      alignmentPeriod  = "300s"
                      perSeriesAligner = "ALIGN_RATE"
                    }
                  }
                }
              },
            ]
            yAxis = { scale = "LINEAR" }
          }
        },
        {
          title = "VM - Disk operations"
          xyChart = {
            dataSets = [
              {
                legendTemplate = "Read $${metric.labels.instance_name}"
                plotType       = "LINE"
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/disk/read_ops_count\" AND (${local.monitoring_instance_filter})"
                    aggregation = {
                      alignmentPeriod  = "300s"
                      perSeriesAligner = "ALIGN_RATE"
                    }
                  }
                }
              },
              {
                legendTemplate = "Write $${metric.labels.instance_name}"
                plotType       = "LINE"
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/disk/write_ops_count\" AND (${local.monitoring_instance_filter})"
                    aggregation = {
                      alignmentPeriod  = "300s"
                      perSeriesAligner = "ALIGN_RATE"
                    }
                  }
                }
              },
            ]
            yAxis = { scale = "LINEAR" }
          }
        },
        {
          title = "Requests per hour"
          xyChart = {
            dataSets = [{
              plotType = "LINE"
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"gce_instance\" AND metric.type=\"logging.googleapis.com/user/${google_logging_metric.http_requests[0].name}\""
                  aggregation = {
                    alignmentPeriod    = "3600s"
                    perSeriesAligner   = "ALIGN_SUM"
                    crossSeriesReducer = "REDUCE_SUM"
                  }
                }
              }
            }]
            yAxis = { scale = "LINEAR" }
          }
        },
        {
          title = "HTTP 5xx responses"
          xyChart = {
            dataSets = [{
              plotType = "LINE"
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"gce_instance\" AND metric.type=\"logging.googleapis.com/user/${google_logging_metric.http_5xx[0].name}\""
                  aggregation = {
                    alignmentPeriod    = "300s"
                    perSeriesAligner   = "ALIGN_SUM"
                    crossSeriesReducer = "REDUCE_SUM"
                  }
                }
              }
            }]
            yAxis = { scale = "LINEAR" }
          }
        },
        {
          title = "HTTPS availability"
          scorecard = {
            timeSeriesQuery = {
              timeSeriesFilter = {
                filter = "resource.type=\"uptime_url\" AND metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND metric.label.check_id=\"${values(google_monitoring_uptime_check_config.https)[0].uptime_check_id}\""
                aggregation = {
                  alignmentPeriod    = "60s"
                  perSeriesAligner   = "ALIGN_FRACTION_TRUE"
                  crossSeriesReducer = "REDUCE_MEAN"
                  groupByFields      = ["metric.label.check_id"]
                }
              }
            }
          }
        },
        {
          title = "Oilscope incidents"
          incidentList = {
            policyNames = concat(
              [for policy in values(google_monitoring_alert_policy.vm_metric) : trimprefix(policy.name, "projects/${var.config.cloud_settings.gcp.project_id}/")],
              [for policy in google_monitoring_alert_policy.vm_unavailable : trimprefix(policy.name, "projects/${var.config.cloud_settings.gcp.project_id}/")],
              [for policy in google_monitoring_alert_policy.http_5xx : trimprefix(policy.name, "projects/${var.config.cloud_settings.gcp.project_id}/")],
              [for policy in values(google_monitoring_alert_policy.https_unavailable) : trimprefix(policy.name, "projects/${var.config.cloud_settings.gcp.project_id}/")],
            )
          }
        },
        {
          title = "Recent HTTP errors"
          logsPanel = {
            resourceNames = ["projects/${var.config.cloud_settings.gcp.project_id}"]
            filter        = "resource.type=\"gce_instance\" AND (${local.logging_instance_filter}) AND log_id(\"docker_json\") AND jsonPayload.log =~ \"DownstreamStatus[^0-9]*5[0-9]{2}[^0-9]\""
          }
        },
      ]
    }
  })
}
