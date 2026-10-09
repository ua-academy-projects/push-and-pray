resource "google_project_service" "monitoring" {
  project            = local.project_id
  service            = "monitoring.googleapis.com"
  disable_on_destroy = false
}

resource "google_monitoring_alert_policy" "metric" {
  for_each = local.metric_alerts

  project      = local.project_id
  display_name = each.value.display_name
  combiner     = "OR"
  severity     = each.value.severity

  documentation {
    content   = each.value.documentation
    mime_type = "text/markdown"
  }

  conditions {
    display_name = each.value.condition_name

    condition_threshold {
      filter = join(" AND ", compact([
        "resource.type=\"${each.value.resource_type}\"",
        "metric.type=\"${each.value.metric_type}\"",
        local.cluster_filter,
        each.value.additional_filter,
      ]))
      comparison      = each.value.comparison
      threshold_value = each.value.threshold
      duration        = each.value.duration

      # Pods and nodes are replaceable. Their time series disappears with the
      # old resource, so missing data must resolve rather than pin an incident
      # open until Cloud Monitoring's default seven-day auto-close.
      evaluation_missing_data = "EVALUATION_MISSING_DATA_INACTIVE"

      aggregations {
        alignment_period     = each.value.alignment_period
        per_series_aligner   = each.value.per_series_aligner
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

  depends_on = [google_project_service.monitoring]
}

resource "google_monitoring_alert_policy" "node_not_ready" {
  project      = local.project_id
  display_name = "${local.resource_prefix}-gke-node-not-ready"
  combiner     = "OR"
  severity     = "ERROR"

  documentation {
    content   = "A GKE worker node has reported a non-ready state for at least five minutes. Inspect the node conditions and GKE events."
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "Node not ready for five minutes"

    condition_threshold {
      filter          = "resource.type=\"k8s_node\" AND metric.type=\"kubernetes.io/node/status_condition\" AND ${local.cluster_filter} AND metric.label.condition=\"Ready\" AND metric.label.status!=\"True\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "300s"

      evaluation_missing_data = "EVALUATION_MISSING_DATA_INACTIVE"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_COUNT_TRUE"
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

  depends_on = [google_project_service.monitoring]
}

resource "google_monitoring_alert_policy" "container_restarts" {
  project      = local.project_id
  display_name = "${local.resource_prefix}-gke-container-restarts"
  combiner     = "OR"
  severity     = "ERROR"

  documentation {
    content   = "A container in the ${local.application_ns} namespace restarted at least three times within 10 minutes. Inspect the pod status, events, and previous container logs."
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "Application container restarted at least three times in 10 minutes"

    condition_prometheus_query_language {
      query = <<-EOT
        sum by (namespace_name, container_name) (
          increase({"kubernetes.io/container/restart_count", monitored_resource="k8s_container", cluster_name="${var.cluster.name}", location="${var.cluster.location}", namespace_name="${local.application_ns}"}[10m])
        ) > 2
      EOT

      duration            = "60s"
      evaluation_interval = "60s"
    }
  }

  notification_channels = local.notification_channels

  alert_strategy {
    auto_close           = "1800s"
    notification_prompts = ["OPENED", "CLOSED"]
  }

  depends_on = [google_project_service.monitoring]
}

resource "google_monitoring_uptime_check_config" "https" {
  project            = local.project_id
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
      host       = local.application_host
      project_id = local.project_id
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

  depends_on = [google_project_service.monitoring]
}

resource "google_monitoring_alert_policy" "https_unavailable" {
  project      = local.project_id
  display_name = "${local.resource_prefix}-https-unavailable"
  combiner     = "OR"
  severity     = "ERROR"

  documentation {
    content   = "Most external probes cannot reach https://${local.application_host}/health successfully. Check DNS, the load balancer, Traefik, the certificate, and the UI workload."
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "Most HTTPS probes fail for two minutes"

    condition_threshold {
      filter          = "resource.type=\"uptime_url\" AND metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND metric.label.check_id=\"${google_monitoring_uptime_check_config.https.uptime_check_id}\""
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
  project = local.project_id

  dashboard_json = jsonencode({
    displayName = "OilScope GKE"
    labels = {
      managed_by = "terraform"
    }
    gridLayout = {
      columns = "2"
      widgets = [
        {
          title = "Nodes - CPU usage"
          xyChart = {
            dataSets = [{
              legendTemplate = "$${resource.labels.node_name}"
              plotType       = "LINE"
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"k8s_node\" AND metric.type=\"kubernetes.io/node/cpu/core_usage_time\" AND ${local.cluster_filter}"
                  aggregation = {
                    alignmentPeriod  = "60s"
                    perSeriesAligner = "ALIGN_RATE"
                  }
                }
              }
            }]
            yAxis = {
              label = "CPU cores"
              scale = "LINEAR"
            }
          }
        },
        {
          title = "Nodes - Memory used"
          xyChart = {
            dataSets = [{
              legendTemplate = "$${resource.labels.node_name}"
              plotType       = "LINE"
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"k8s_node\" AND metric.type=\"kubernetes.io/node/memory/used_bytes\" AND ${local.cluster_filter}"
                  aggregation = {
                    alignmentPeriod  = "60s"
                    perSeriesAligner = "ALIGN_MEAN"
                  }
                }
              }
            }]
            yAxis = {
              label = "Bytes"
              scale = "LINEAR"
            }
          }
        },
        {
          title = "Nodes - Ephemeral storage used"
          xyChart = {
            dataSets = [{
              legendTemplate = "$${resource.labels.node_name}"
              plotType       = "LINE"
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"k8s_node\" AND metric.type=\"kubernetes.io/node/ephemeral_storage/used_bytes\" AND ${local.cluster_filter}"
                  aggregation = {
                    alignmentPeriod  = "300s"
                    perSeriesAligner = "ALIGN_MEAN"
                  }
                }
              }
            }]
            yAxis = {
              label = "Bytes"
              scale = "LINEAR"
            }
          }
        },
        {
          title = "Pods - Count by namespace"
          xyChart = {
            dataSets = [{
              legendTemplate     = "$${metric.labels.namespace_name}"
              plotType           = "STACKED_AREA"
              minAlignmentPeriod = "60s"
              timeSeriesQuery = {
                prometheusQuery = <<-EOT
                  count by (namespace_name) (
                    max by (namespace_name, pod_name) (
                      {"kubernetes.io/container/uptime", monitored_resource="k8s_container", cluster_name="${var.cluster.name}", location="${var.cluster.location}"}
                    )
                  )
                EOT
              }
            }]
            yAxis = {
              label = "Pods"
              scale = "LINEAR"
            }
          }
        },
        {
          title = "Namespaces - Container CPU usage"
          xyChart = {
            dataSets = [{
              legendTemplate = "$${resource.labels.namespace_name}"
              plotType       = "LINE"
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"k8s_container\" AND metric.type=\"kubernetes.io/container/cpu/core_usage_time\" AND ${local.cluster_filter}"
                  aggregation = {
                    alignmentPeriod    = "60s"
                    perSeriesAligner   = "ALIGN_RATE"
                    crossSeriesReducer = "REDUCE_SUM"
                    groupByFields      = ["resource.label.namespace_name"]
                  }
                }
              }
            }]
            yAxis = {
              label = "CPU cores"
              scale = "LINEAR"
            }
          }
        },
        {
          title = "Namespaces - Container memory used"
          xyChart = {
            dataSets = [{
              legendTemplate = "$${resource.labels.namespace_name}"
              plotType       = "LINE"
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"k8s_container\" AND metric.type=\"kubernetes.io/container/memory/used_bytes\" AND ${local.cluster_filter}"
                  aggregation = {
                    alignmentPeriod    = "60s"
                    perSeriesAligner   = "ALIGN_MEAN"
                    crossSeriesReducer = "REDUCE_SUM"
                    groupByFields      = ["resource.label.namespace_name"]
                  }
                }
              }
            }]
            yAxis = {
              label = "Bytes"
              scale = "LINEAR"
            }
          }
        },
        {
          title = "Namespaces - Container restarts"
          xyChart = {
            dataSets = [{
              legendTemplate = "$${resource.labels.namespace_name}"
              plotType       = "STACKED_BAR"
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"k8s_container\" AND metric.type=\"kubernetes.io/container/restart_count\" AND ${local.cluster_filter}"
                  aggregation = {
                    alignmentPeriod    = "300s"
                    perSeriesAligner   = "ALIGN_DELTA"
                    crossSeriesReducer = "REDUCE_SUM"
                    groupByFields      = ["resource.label.namespace_name"]
                  }
                }
              }
            }]
            yAxis = {
              label = "Restarts"
              scale = "LINEAR"
            }
          }
        },
        {
          title = "Namespaces - Pod network traffic"
          xyChart = {
            dataSets = [
              {
                legendTemplate = "Received $${resource.labels.namespace_name}"
                plotType       = "LINE"
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"k8s_pod\" AND metric.type=\"kubernetes.io/pod/network/received_bytes_count\" AND ${local.cluster_filter}"
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_SUM"
                      groupByFields      = ["resource.label.namespace_name"]
                    }
                  }
                }
              },
              {
                legendTemplate = "Sent $${resource.labels.namespace_name}"
                plotType       = "LINE"
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"k8s_pod\" AND metric.type=\"kubernetes.io/pod/network/sent_bytes_count\" AND ${local.cluster_filter}"
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_SUM"
                      groupByFields      = ["resource.label.namespace_name"]
                    }
                  }
                }
              },
            ]
            yAxis = {
              label = "Bytes per second"
              scale = "LINEAR"
            }
          }
        },
        {
          title = "HTTPS availability"
          scorecard = {
            timeSeriesQuery = {
              timeSeriesFilter = {
                filter = "resource.type=\"uptime_url\" AND metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND metric.label.check_id=\"${google_monitoring_uptime_check_config.https.uptime_check_id}\""
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
          title = "GKE incidents"
          incidentList = {
            policyNames = concat(
              [for policy in values(google_monitoring_alert_policy.metric) : trimprefix(policy.name, "projects/${local.project_id}/")],
              [trimprefix(google_monitoring_alert_policy.node_not_ready.name, "projects/${local.project_id}/")],
              [trimprefix(google_monitoring_alert_policy.container_restarts.name, "projects/${local.project_id}/")],
              [trimprefix(google_monitoring_alert_policy.https_unavailable.name, "projects/${local.project_id}/")],
            )
          }
        },
      ]
    }
  })

  depends_on = [google_project_service.monitoring]
}
