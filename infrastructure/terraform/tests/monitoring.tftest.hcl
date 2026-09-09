mock_provider "google" {}
mock_provider "aws" {}

run "gcp_cpu_monitoring" {
  command = plan

  module {
    source = "./modules/gcp_monitoring"
  }

  variables {
    resource_prefix = "oilscope-test"
    monitoring = {
      enabled            = true
      notification_email = "alerts@example.com"
      cpu = {
        enabled           = true
        threshold_percent = 80
        duration_minutes  = 5
      }
    }
    vms = {
      history = { name = "oilscope-test-history", instance_id = "1111111111111111111" }
      fetcher = { name = "oilscope-test-fetcher", instance_id = "2222222222222222222" }
    }
  }

  assert {
    condition = (
      length(google_monitoring_dashboard.cpu) == 1 &&
      length(google_monitoring_notification_channel.email) == 1 &&
      toset(keys(google_monitoring_alert_policy.cpu)) == toset(["history", "fetcher"])
    )
    error_message = "Enabled GCP monitoring must create one dashboard/channel and one alert per managed VM."
  }

  assert {
    condition = alltrue([
      for name, alert in google_monitoring_alert_policy.cpu :
      alert.conditions[0].condition_threshold[0].threshold_value == 0.8 &&
      alert.conditions[0].condition_threshold[0].duration == "300s" &&
      strcontains(alert.conditions[0].condition_threshold[0].filter, var.vms[name].instance_id)
    ])
    error_message = "GCP alerts must translate the common threshold to a utilization ratio and use managed instance IDs."
  }

  assert {
    condition = alltrue([
      for vm in values(var.vms) : strcontains(google_monitoring_dashboard.cpu[0].dashboard_json, vm.instance_id)
    ])
    error_message = "The GCP dashboard must select the instance IDs supplied by the managed VM module."
  }
}

run "gcp_monitoring_disabled" {
  command = plan

  module {
    source = "./modules/gcp_monitoring"
  }

  variables {
    resource_prefix = "oilscope-test"
    monitoring = {
      enabled            = false
      notification_email = "alerts@example.com"
      cpu                = { enabled = true, threshold_percent = 80, duration_minutes = 5 }
    }
    vms = {
      history = { name = "oilscope-test-history", instance_id = "1111111111111111111" }
    }
  }

  assert {
    condition = (
      length(google_monitoring_dashboard.cpu) == 0 &&
      length(google_monitoring_notification_channel.email) == 0 &&
      length(google_monitoring_alert_policy.cpu) == 0
    )
    error_message = "Disabled GCP monitoring must create no resources."
  }
}

run "aws_cpu_monitoring" {
  command = plan

  module {
    source = "./modules/aws_monitoring"
  }

  variables {
    resource_prefix = "oilscope-test"
    monitoring = {
      enabled            = true
      notification_email = "alerts@example.com"
      cpu                = { enabled = true, threshold_percent = 80, duration_minutes = 5 }
    }
    vms = {
      history = { name = "oilscope-test-history", instance_id = "i-0123456789abcdef0" }
      fetcher = { name = "oilscope-test-fetcher", instance_id = "i-0fedcba9876543210" }
    }
    tags = { managed_by = "terraform" }
  }

  assert {
    condition = (
      length(aws_cloudwatch_dashboard.cpu) == 1 &&
      length(aws_sns_topic.monitoring) == 1 &&
      length(aws_sns_topic_subscription.email) == 1 &&
      toset(keys(aws_cloudwatch_metric_alarm.cpu)) == toset(["history", "fetcher"])
    )
    error_message = "Enabled AWS monitoring must create one dashboard/topic/subscription and one alarm per managed VM."
  }

  assert {
    condition = alltrue([
      for name, alarm in aws_cloudwatch_metric_alarm.cpu :
      alarm.threshold == 80 &&
      alarm.evaluation_periods == 5 &&
      alarm.dimensions.InstanceId == var.vms[name].instance_id
    ])
    error_message = "AWS alarms must propagate the common threshold/duration and use managed instance IDs."
  }

  assert {
    condition = alltrue([
      for vm in values(var.vms) : strcontains(aws_cloudwatch_dashboard.cpu[0].dashboard_body, vm.instance_id)
    ])
    error_message = "The AWS dashboard must select the instance IDs supplied by the managed VM module."
  }
}

run "aws_monitoring_without_vms" {
  command = plan

  module {
    source = "./modules/aws_monitoring"
  }

  variables {
    resource_prefix = "oilscope-test"
    monitoring = {
      enabled            = true
      notification_email = "alerts@example.com"
      cpu                = { enabled = true, threshold_percent = 80, duration_minutes = 5 }
    }
    vms  = {}
    tags = {}
  }

  assert {
    condition = (
      length(aws_cloudwatch_dashboard.cpu) == 0 &&
      length(aws_sns_topic.monitoring) == 0 &&
      length(aws_sns_topic_subscription.email) == 0 &&
      length(aws_cloudwatch_metric_alarm.cpu) == 0
    )
    error_message = "AWS monitoring with no AWS VMs must create no resources."
  }
}
