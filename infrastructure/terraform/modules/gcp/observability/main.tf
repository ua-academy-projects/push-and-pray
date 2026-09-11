locals {
  synthetic_host = trimsuffix(trimprefix(var.synthetic_url, "https://"), "/")
  notification_channels = [
    google_monitoring_notification_channel.email.name
  ]
}

resource "google_monitoring_notification_channel" "email" {
  display_name = "${var.resource_prefix} alerts"
  type         = "email"
  labels = {
    email_address = var.alert_email
  }
}

resource "google_logging_metric" "http_5xx" {
  name        = "${var.resource_prefix}-http-5xx"
  description = "OilScope application HTTP 5xx responses"
  filter      = <<-EOT
    resource.type="gce_instance"
    log_id("oilscope_application")
    (jsonPayload.MESSAGE =~ "HTTP/[0-9.]+.* 5[0-9][0-9]" OR textPayload =~ "HTTP/[0-9.]+.* 5[0-9][0-9]")
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

resource "google_monitoring_uptime_check_config" "application" {
  display_name = "${var.resource_prefix} HTTPS"
  timeout      = "10s"
  period       = "300s"

  monitored_resource {
    type = "uptime_url"
    labels = {
      host       = local.synthetic_host
      project_id = var.project_id
    }
  }

  http_check {
    path           = "/"
    port           = 443
    request_method = "GET"
    use_ssl        = true
    validate_ssl   = true
  }
}

resource "google_monitoring_alert_policy" "cpu_high" {
  for_each = var.instances

  display_name          = "${var.resource_prefix}-gcp-${each.key}-cpu-high"
  combiner              = "OR"
  notification_channels = local.notification_channels

  conditions {
    display_name = "CPU above 80% for 5 minutes"
    condition_threshold {
      filter          = "resource.type = \"gce_instance\" AND resource.label.instance_id = \"${each.value.instance_id}\" AND metric.type = \"compute.googleapis.com/instance/cpu/utilization\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0.8
      duration        = "300s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  alert_strategy {
    auto_close           = "1800s"
    notification_prompts = ["OPENED", "CLOSED"]
  }
}

resource "google_monitoring_alert_policy" "memory_high" {
  for_each = var.instances

  display_name          = "${var.resource_prefix}-gcp-${each.key}-memory-high"
  combiner              = "OR"
  notification_channels = local.notification_channels

  conditions {
    display_name = "Memory above 80% for 5 minutes"
    condition_threshold {
      filter          = "resource.type = \"gce_instance\" AND resource.label.instance_id = \"${each.value.instance_id}\" AND metric.type = \"agent.googleapis.com/memory/percent_used\" AND metric.label.state = \"used\""
      comparison      = "COMPARISON_GT"
      threshold_value = 80
      duration        = "300s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  alert_strategy {
    auto_close           = "1800s"
    notification_prompts = ["OPENED", "CLOSED"]
  }
}

resource "google_monitoring_alert_policy" "disk_high" {
  for_each = var.instances

  display_name          = "${var.resource_prefix}-gcp-${each.key}-disk-high"
  combiner              = "OR"
  notification_channels = local.notification_channels

  conditions {
    display_name = "Disk above 80% for 10 minutes"
    condition_threshold {
      filter          = "resource.type = \"gce_instance\" AND resource.label.instance_id = \"${each.value.instance_id}\" AND metric.type = \"agent.googleapis.com/disk/percent_used\""
      comparison      = "COMPARISON_GT"
      threshold_value = 80
      duration        = "600s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  alert_strategy {
    auto_close           = "1800s"
    notification_prompts = ["OPENED", "CLOSED"]
  }
}

resource "google_monitoring_alert_policy" "http_5xx" {
  display_name          = "${var.resource_prefix}-gcp-http-5xx"
  combiner              = "OR"
  notification_channels = local.notification_channels

  conditions {
    display_name = "At least one HTTP 5xx in 5 minutes"
    condition_threshold {
      filter          = "metric.type = \"logging.googleapis.com/user/${google_logging_metric.http_5xx.name}\" AND resource.type = \"gce_instance\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_SUM"
      }
    }
  }

  alert_strategy {
    auto_close           = "1800s"
    notification_prompts = ["OPENED", "CLOSED"]
  }
}

resource "google_monitoring_alert_policy" "uptime" {
  display_name          = "${var.resource_prefix}-gcp-https-unavailable"
  combiner              = "OR"
  notification_channels = local.notification_channels

  conditions {
    display_name = "HTTPS failed for 10 minutes"
    condition_threshold {
      filter          = "metric.type = \"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.type = \"uptime_url\" AND metric.label.check_id = \"${google_monitoring_uptime_check_config.application.uptime_check_id}\""
      comparison      = "COMPARISON_LT"
      threshold_value = 1
      duration        = "600s"
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_FRACTION_TRUE"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields      = ["resource.label.host"]
      }
    }
  }

  alert_strategy {
    auto_close           = "1800s"
    notification_prompts = ["OPENED", "CLOSED"]
  }
}
