mock_provider "google" {}
run "defaults" {
  command = plan
  module { source = "./modules/gcp/monitoring" }
  variables {
    config = { "name_prefix" : "oilscope", "environment" : "dev", "clouds" : { "gcp" : { "project_id" : "example-project" } }, "vms" : { "ui" : { "role" : "ui" }, "history" : { "role" : "history" } } }
    vms    = { "ui" : { "instance_id" : "12345", "zone" : "europe-central2-a" }, "history" : { "instance_id" : "12346", "zone" : "europe-central2-a" } }
  }
  assert {
    condition     = length(google_logging_metric.http) == 2 && length(google_monitoring_alert_policy.vm) == 0
    error_message = "Default creates logs, not alarms."
  }
  assert {
    condition     = length(output.agent_configurations) == 1 && length(yamldecode(output.agent_configurations["ui"]).metrics.service.pipelines.default_pipeline.receivers) == 0
    error_message = "Default UI config must disable host metrics."
  }
  assert {
    condition     = google_logging_project_exclusion.traefik_default[0].filter == google_logging_project_sink.traefik[0].filter
    error_message = "Default exclusion must exactly match dedicated routing."
  }
}

run "disabled" {
  command = plan
  module { source = "./modules/gcp/monitoring" }
  variables {
    config = { "name_prefix" : "oilscope", "environment" : "dev", "clouds" : { "gcp" : { "project_id" : "example-project" } }, "vms" : { "ui" : { "role" : "ui" }, "history" : { "role" : "history" } }, "monitoring" : { "enabled" : false, "alarms_enabled" : true, "agent_metrics_enabled" : true, "dashboard_enabled" : true } }
    vms    = { "ui" : { "instance_id" : "12345", "zone" : "europe-central2-a" }, "history" : { "instance_id" : "12346", "zone" : "europe-central2-a" } }
  }
  assert {
    condition     = length(google_project_service.monitoring) == 0 && length(google_logging_metric.http) == 0 && length(output.agent_configurations) == 0
    error_message = "Master disable must suppress resources."
  }
}

run "aws_only" {
  command = plan
  module { source = "./modules/gcp/monitoring" }
  variables {
    config = { "name_prefix" : "oilscope", "environment" : "dev", "clouds" : {}, "vms" : { "ui" : { "role" : "ui" }, "history" : { "role" : "history" } }, "monitoring" : { "alarms_enabled" : true } }
    vms    = {}
  }
  assert {
    condition     = length(google_project_service.monitoring) == 0 && length(google_monitoring_notification_channel.email) == 0
    error_message = "AWS-only inputs create no GCP resources."
  }
}

run "full" {
  command = plan
  module { source = "./modules/gcp/monitoring" }
  variables {
    config = { "name_prefix" : "oilscope", "environment" : "dev", "clouds" : { "gcp" : { "project_id" : "example-project" } }, "vms" : { "ui" : { "role" : "ui" }, "history" : { "role" : "history" } }, "monitoring" : { "email_recipients" : ["operator@example.com", "operator@example.com"], "alarms_enabled" : true, "agent_metrics_enabled" : true, "dashboard_enabled" : true } }
    vms    = { "ui" : { "instance_id" : "12345", "zone" : "europe-central2-a" }, "history" : { "instance_id" : "12346", "zone" : "europe-central2-a" } }
  }
  assert {
    condition     = length(google_monitoring_alert_policy.vm) == 6 && length(google_monitoring_alert_policy.missing) == 4 && length(google_monitoring_alert_policy.http) == 2
    error_message = "Expected host, absence, and HTTP policies."
  }
  assert {
    condition     = google_monitoring_alert_policy.vm["ui-cpu"].conditions[0].condition_threshold[0].threshold_value == 0.8 && google_monitoring_alert_policy.vm["ui-memory"].conditions[0].condition_threshold[0].threshold_value == 85
    error_message = "CPU and memory units differ."
  }
  assert {
    condition     = length(google_monitoring_notification_channel.email) == 1
    error_message = "Recipients must deduplicate."
  }
  assert {
    condition     = length(yamldecode(output.agent_configurations["history"]).logging.service.pipelines.default_pipeline.receivers) == 0 && length(yamldecode(output.agent_configurations["history"]).logging.receivers) == 0
    error_message = "History must not collect Traefik or default syslog."
  }
  assert {
    condition     = strcontains(google_monitoring_alert_policy.vm["ui-disk"].conditions[0].condition_threshold[0].filter, "metric.labels.state") && !strcontains(google_monitoring_alert_policy.vm["ui-disk"].conditions[0].condition_threshold[0].filter, "fstype")
    error_message = "Disk uses GCP labels, not AWS dimensions."
  }
}

run "logs_off" {
  command = plan
  module { source = "./modules/gcp/monitoring" }
  variables {
    config = { "name_prefix" : "oilscope", "environment" : "dev", "clouds" : { "gcp" : { "project_id" : "example-project" } }, "vms" : { "ui" : { "role" : "ui" }, "history" : { "role" : "history" } }, "monitoring" : { "email_recipients" : ["operator@example.com", "operator@example.com"], "alarms_enabled" : true, "agent_metrics_enabled" : true, "dashboard_enabled" : true, "logs_enabled" : false } }
    vms    = { "ui" : { "instance_id" : "12345", "zone" : "europe-central2-a" }, "history" : { "instance_id" : "12346", "zone" : "europe-central2-a" } }
  }
  assert {
    condition     = length(google_logging_project_sink.traefik) == 0 && length(google_logging_project_exclusion.traefik_default) == 0 && length(google_monitoring_alert_policy.http) == 0
    error_message = "Disable log routing and HTTP alarms together."
  }
}

run "no_ui" {
  command = plan
  module { source = "./modules/gcp/monitoring" }
  variables {
    config = { "name_prefix" : "oilscope", "environment" : "dev", "clouds" : { "gcp" : { "project_id" : "example-project" } }, "vms" : { "ui" : { "role" : "ui" }, "history" : { "role" : "history" } }, "monitoring" : { "email_recipients" : ["operator@example.com", "operator@example.com"], "alarms_enabled" : true, "agent_metrics_enabled" : true, "dashboard_enabled" : true } }
    vms    = { "history" : { "instance_id" : "12346", "zone" : "europe-central2-a" } }
  }
  assert {
    condition     = length(google_logging_metric.http) == 0 && length(output.agent_configurations) == 1
    error_message = "No UI means no access-log resources."
  }
}

run "synthetics" {
  command = plan
  module { source = "./modules/gcp/monitoring" }
  variables {
    config = { "name_prefix" : "oilscope", "environment" : "dev", "clouds" : { "gcp" : { "project_id" : "example-project" } }, "vms" : { "ui" : { "role" : "ui" }, "history" : { "role" : "history" } }, "monitoring" : { "email_recipients" : ["operator@example.com", "operator@example.com"], "alarms_enabled" : true, "agent_metrics_enabled" : true, "dashboard_enabled" : true, "synthetics" : { "enabled" : true, "hostname" : "oilscope.example.com" } } }
    vms    = { "ui" : { "instance_id" : "12345", "zone" : "europe-central2-a" }, "history" : { "instance_id" : "12346", "zone" : "europe-central2-a" } }
  }
  assert {
    condition     = length(google_monitoring_uptime_check_config.health) == 1 && length(google_monitoring_alert_policy.uptime) == 1
    error_message = "Create a check and its availability policy."
  }
  assert {
    condition     = google_monitoring_uptime_check_config.health[0].http_check[0].validate_ssl && google_monitoring_uptime_check_config.health[0].period == "300s"
    error_message = "Require TLS validation and correct cadence."
  }
  assert {
    condition     = google_monitoring_alert_policy.uptime[0].conditions[0].condition_threshold[0].threshold_value == 1
    error_message = "Require multiple failed locations."
  }
}

run "bad_email" {
  command = plan
  module { source = "./modules/gcp/monitoring" }
  variables {
    config = { "name_prefix" : "oilscope", "environment" : "dev", "clouds" : { "gcp" : { "project_id" : "example-project" } }, "vms" : { "ui" : { "role" : "ui" }, "history" : { "role" : "history" } }, "monitoring" : { "email_recipients" : ["bad"] } }
    vms    = { "ui" : { "instance_id" : "12345", "zone" : "europe-central2-a" }, "history" : { "instance_id" : "12346", "zone" : "europe-central2-a" } }
  }
  expect_failures = [var.config]
}

run "missing_recipients" {
  command = plan
  module { source = "./modules/gcp/monitoring" }
  variables {
    config = { "name_prefix" : "oilscope", "environment" : "dev", "clouds" : { "gcp" : { "project_id" : "example-project" } }, "vms" : { "ui" : { "role" : "ui" }, "history" : { "role" : "history" } }, "monitoring" : { "alarms_enabled" : true } }
    vms    = { "ui" : { "instance_id" : "12345", "zone" : "europe-central2-a" }, "history" : { "instance_id" : "12346", "zone" : "europe-central2-a" } }
  }
  expect_failures = [var.config]
}

run "invalid_period" {
  command = plan
  module { source = "./modules/gcp/monitoring" }
  variables {
    config = { "name_prefix" : "oilscope", "environment" : "dev", "clouds" : { "gcp" : { "project_id" : "example-project" } }, "vms" : { "ui" : { "role" : "ui" }, "history" : { "role" : "history" } }, "monitoring" : { "synthetics" : { "enabled" : true, "hostname" : "example.com", "period_minutes" : 30 } } }
    vms    = { "ui" : { "instance_id" : "12345", "zone" : "europe-central2-a" }, "history" : { "instance_id" : "12346", "zone" : "europe-central2-a" } }
  }
  expect_failures = [var.config]
}

run "invalid_threshold" {
  command = plan
  module { source = "./modules/gcp/monitoring" }
  variables {
    config = { "name_prefix" : "oilscope", "environment" : "dev", "clouds" : { "gcp" : { "project_id" : "example-project" } }, "vms" : { "ui" : { "role" : "ui" }, "history" : { "role" : "history" } }, "monitoring" : { "memory_threshold_percent" : 101 } }
    vms    = { "ui" : { "instance_id" : "12345", "zone" : "europe-central2-a" }, "history" : { "instance_id" : "12346", "zone" : "europe-central2-a" } }
  }
  expect_failures = [var.config]
}
