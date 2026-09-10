mock_provider "aws" {}
mock_provider "archive" {}
run "defaults" {
  command = plan
  module { source = "./modules/aws/monitoring" }
  variables {
    config = { "name_prefix" : "oilscope", "environment" : "dev", "region" : "eu-central", "region_map" : { "eu-central" : { "aws" : { "region" : "eu-central-1" } } }, "vms" : { "ui" : { "role" : "ui" }, "history" : { "role" : "history" } } }
    vms    = { "ui" : { "instance_id" : "i-0123456789abcdef0" }, "history" : { "instance_id" : "i-0123456789abcdef1" } }
  }
  assert {
    condition     = length(aws_cloudwatch_log_group.traefik) == 1 && length(aws_cloudwatch_metric_alarm.vm) == 0
    error_message = "Defaults must preserve the log group without paid alarms."
  }
  assert {
    condition     = length(aws_synthetics_canary.health) == 0 && length(aws_cloudwatch_dashboard.operations) == 0
    error_message = "Synthetics and dashboard must be opt-in."
  }
  assert {
    condition     = length(output.agent_configurations) == 1 && !can(jsondecode(output.agent_configurations["ui"]).metrics)
    error_message = "Logs-only configuration should be emitted only for the UI."
  }
}

run "disabled" {
  command = plan
  module { source = "./modules/aws/monitoring" }
  variables {
    config = { "name_prefix" : "oilscope", "environment" : "dev", "region" : "eu-central", "region_map" : { "eu-central" : { "aws" : { "region" : "eu-central-1" } } }, "vms" : { "ui" : { "role" : "ui" }, "history" : { "role" : "history" } }, "monitoring" : { "enabled" : false, "email_recipients" : ["operator@example.com"], "agent_metrics_enabled" : true, "alarms_enabled" : true, "dashboard_enabled" : true } }
    vms    = { "ui" : { "instance_id" : "i-0123456789abcdef0" }, "history" : { "instance_id" : "i-0123456789abcdef1" } }
  }
  assert {
    condition     = length(aws_cloudwatch_log_group.traefik) == 0 && length(aws_sns_topic.alerts) == 0 && length(aws_cloudwatch_metric_alarm.vm) == 0 && length(output.agent_configurations) == 0
    error_message = "Master switch must suppress all monitoring resources."
  }
}

run "no_aws_vms" {
  command = plan
  module { source = "./modules/aws/monitoring" }
  variables {
    config = { "name_prefix" : "oilscope", "environment" : "dev", "region" : "eu-central", "region_map" : { "eu-central" : { "aws" : { "region" : "eu-central-1" } } }, "vms" : { "ui" : { "role" : "ui" }, "history" : { "role" : "history" } }, "monitoring" : { "email_recipients" : ["operator@example.com"], "alarms_enabled" : true, "dashboard_enabled" : true } }
    vms    = {}
  }
  assert {
    condition     = length(aws_cloudwatch_log_group.traefik) == 0 && length(aws_sns_topic_subscription.email) == 0 && length(aws_cloudwatch_dashboard.operations) == 0
    error_message = "A GCP-only deployment must not create AWS monitoring."
  }
}

run "full_metrics" {
  command = plan
  module { source = "./modules/aws/monitoring" }
  variables {
    config = { "name_prefix" : "oilscope", "environment" : "dev", "region" : "eu-central", "region_map" : { "eu-central" : { "aws" : { "region" : "eu-central-1" } } }, "vms" : { "ui" : { "role" : "ui" }, "history" : { "role" : "history" } }, "monitoring" : { "email_recipients" : ["operator@example.com", "operator@example.com"], "agent_metrics_enabled" : true, "alarms_enabled" : true, "dashboard_enabled" : true } }
    vms    = { "ui" : { "instance_id" : "i-0123456789abcdef0" }, "history" : { "instance_id" : "i-0123456789abcdef1" } }
  }
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.vm) == 10 && length(aws_cloudwatch_metric_alarm.http) == 2
    error_message = "Two VMs need five host signals each and two HTTP alarms."
  }
  assert {
    condition     = length(aws_sns_topic_subscription.email) == 1
    error_message = "Duplicate recipients must not create duplicate subscriptions."
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.vm["ui-disk"].dimensions == tomap({ InstanceId = "i-0123456789abcdef0", path = "/", fstype = "ext4" })
    error_message = "Disk dimensions must match the generated agent configuration."
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.vm["ui-agent_missing"].treat_missing_data == "breaching" && aws_cloudwatch_metric_alarm.http["HTTP500Count"].treat_missing_data == "notBreaching"
    error_message = "Missing telemetry and missing error events need different behavior."
  }
  assert {
    condition     = !can(jsondecode(output.agent_configurations["history"]).logs) && can(jsondecode(output.agent_configurations["ui"]).logs)
    error_message = "Only UI VMs collect Traefik logs."
  }
}

run "logs_off" {
  command = plan
  module { source = "./modules/aws/monitoring" }
  variables {
    config = { "name_prefix" : "oilscope", "environment" : "dev", "region" : "eu-central", "region_map" : { "eu-central" : { "aws" : { "region" : "eu-central-1" } } }, "vms" : { "ui" : { "role" : "ui" }, "history" : { "role" : "history" } }, "monitoring" : { "logs_enabled" : false, "agent_metrics_enabled" : true, "alarms_enabled" : true, "email_recipients" : ["operator@example.com"] } }
    vms    = { "ui" : { "instance_id" : "i-0123456789abcdef0" }, "history" : { "instance_id" : "i-0123456789abcdef1" } }
  }
  assert {
    condition     = length(aws_cloudwatch_log_metric_filter.http) == 0 && length(aws_cloudwatch_metric_alarm.http) == 0
    error_message = "Disabling logs must remove filters and HTTP alarms."
  }
}

run "reject_no_recipients" {
  command = plan
  module { source = "./modules/aws/monitoring" }
  variables {
    config = { "name_prefix" : "oilscope", "environment" : "dev", "region" : "eu-central", "region_map" : { "eu-central" : { "aws" : { "region" : "eu-central-1" } } }, "vms" : { "ui" : { "role" : "ui" }, "history" : { "role" : "history" } }, "monitoring" : { "alarms_enabled" : true } }
    vms    = { "ui" : { "instance_id" : "i-0123456789abcdef0" }, "history" : { "instance_id" : "i-0123456789abcdef1" } }
  }
  expect_failures = [var.config]
}

run "reject_threshold" {
  command = plan
  module { source = "./modules/aws/monitoring" }
  variables {
    config = { "name_prefix" : "oilscope", "environment" : "dev", "region" : "eu-central", "region_map" : { "eu-central" : { "aws" : { "region" : "eu-central-1" } } }, "vms" : { "ui" : { "role" : "ui" }, "history" : { "role" : "history" } }, "monitoring" : { "cpu_threshold_percent" : 101 } }
    vms    = { "ui" : { "instance_id" : "i-0123456789abcdef0" }, "history" : { "instance_id" : "i-0123456789abcdef1" } }
  }
  expect_failures = [var.config]
}

run "reject_synthetic_host" {
  command = plan
  module { source = "./modules/aws/monitoring" }
  variables {
    config = { "name_prefix" : "oilscope", "environment" : "dev", "region" : "eu-central", "region_map" : { "eu-central" : { "aws" : { "region" : "eu-central-1" } } }, "vms" : { "ui" : { "role" : "ui" }, "history" : { "role" : "history" } }, "monitoring" : { "synthetics" : { "enabled" : true, "hostname" : "https://bad.example.com" } } }
    vms    = { "ui" : { "instance_id" : "i-0123456789abcdef0" }, "history" : { "instance_id" : "i-0123456789abcdef1" } }
  }
  expect_failures = [var.config]
}

run "synthetic" {
  command = plan
  module { source = "./modules/aws/monitoring" }
  variables {
    config = { "name_prefix" : "oilscope", "environment" : "dev", "region" : "eu-central", "region_map" : { "eu-central" : { "aws" : { "region" : "eu-central-1" } } }, "vms" : { "ui" : { "role" : "ui" }, "history" : { "role" : "history" } }, "monitoring" : { "email_recipients" : ["operator@example.com"], "alarms_enabled" : true, "synthetics" : { "enabled" : true, "hostname" : "oilscope.example.com" } } }
    vms    = { "ui" : { "instance_id" : "i-0123456789abcdef0" }, "history" : { "instance_id" : "i-0123456789abcdef1" } }
  }
  assert {
    condition     = length(aws_synthetics_canary.health) == 1 && length(aws_cloudwatch_metric_alarm.synthetic) == 1
    error_message = "Enabled synthetic needs a canary and availability alarm."
  }
  assert {
    condition     = aws_synthetics_canary.health[0].delete_lambda && !aws_s3_bucket.canary[0].force_destroy
    error_message = "Delete implicit Lambda but protect artifact storage."
  }
  assert {
    condition     = aws_synthetics_canary.health[0].schedule[0].expression == "rate(5 minutes)"
    error_message = "Default synthetic cadence must be five minutes."
  }
}
