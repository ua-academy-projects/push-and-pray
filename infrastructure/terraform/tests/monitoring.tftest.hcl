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
      google_monitoring_notification_channel.email[0].labels.email_address == var.monitoring.notification_email &&
      toset(keys(google_monitoring_alert_policy.cpu)) == toset(["history", "fetcher"]) &&
      length(google_monitoring_alert_policy.lifecycle) == 0 &&
      !strcontains(google_monitoring_dashboard.cpu[0].dashboard_json, "compute.googleapis.com/instance/uptime")
    )
    error_message = "Enabled GCP monitoring must retain CPU resources without adding a misleading instance-uptime signal."
  }

  assert {
    condition = alltrue([
      for name, alert in google_monitoring_alert_policy.cpu :
      alert.conditions[0].condition_threshold[0].threshold_value == 0.8 &&
      alert.conditions[0].condition_threshold[0].duration == "300s" &&
      strcontains(alert.conditions[0].condition_threshold[0].filter, var.vms[name].instance_id) &&
      length(alert.notification_channels) == 1
    ])
    error_message = "GCP alerts must translate the common threshold to a utilization ratio, use managed instance IDs, and notify the configured email channel."
  }

  assert {
    condition = alltrue([
      for vm in values(var.vms) : strcontains(google_monitoring_dashboard.cpu[0].dashboard_json, vm.instance_id)
    ])
    error_message = "The GCP dashboard must select the instance IDs supplied by the managed VM module."
  }
}

run "gcp_custom_cpu_threshold" {
  command = plan

  module {
    source = "./modules/gcp_monitoring"
  }

  variables {
    resource_prefix = "oilscope-test"
    monitoring = {
      enabled            = true
      notification_email = "alerts@example.com"
      cpu                = { enabled = true, threshold_percent = 20, duration_minutes = 3 }
    }
    vms = {
      history = { name = "oilscope-test-history", instance_id = "1111111111111111111" }
    }
  }

  assert {
    condition = (
      google_monitoring_alert_policy.cpu["history"].conditions[0].condition_threshold[0].threshold_value == 0.2 &&
      google_monitoring_alert_policy.cpu["history"].conditions[0].condition_threshold[0].duration == "180s" &&
      length(google_monitoring_dashboard.cpu) == 1
    )
    error_message = "A custom GCP CPU threshold and duration must update the stable per-VM policy while retaining the dashboard."
  }
}

run "gcp_lifecycle_monitoring" {
  command = plan

  module {
    source = "./modules/gcp_monitoring"
  }

  variables {
    resource_prefix = "oilscope-test"
    monitoring = {
      enabled            = true
      notification_email = "alerts@example.com"
      cpu                = { enabled = false, threshold_percent = 80, duration_minutes = 5 }
      lifecycle = {
        enabled       = true
        notify_states = ["stopped", "terminated"]
      }
    }
    vms = {
      history = { name = "oilscope-test-history", instance_id = "1111111111111111111" }
      fetcher = { name = "oilscope-test-fetcher", instance_id = "2222222222222222222" }
    }
  }

  assert {
    condition = (
      length(google_monitoring_notification_channel.email) == 1 &&
      length(google_monitoring_dashboard.cpu) == 0 &&
      length(google_monitoring_alert_policy.cpu) == 0 &&
      toset(keys(google_monitoring_alert_policy.lifecycle)) == toset(["history", "fetcher"])
    )
    error_message = "GCP lifecycle monitoring must create one log-matched policy per managed VM and reuse one notification channel."
  }

  assert {
    condition = alltrue([
      for name, alert in google_monitoring_alert_policy.lifecycle :
      length(alert.conditions[0].condition_matched_log) == 1 &&
      strcontains(alert.conditions[0].condition_matched_log[0].filter, var.vms[name].instance_id) &&
      strcontains(alert.conditions[0].condition_matched_log[0].filter, "v1.compute.instances.stop") &&
      strcontains(alert.conditions[0].condition_matched_log[0].filter, "compute.instances.hostError") &&
      strcontains(alert.conditions[0].condition_matched_log[0].filter, "compute.instances.guestTerminate") &&
      strcontains(alert.conditions[0].condition_matched_log[0].filter, "compute.instances.terminateOnHostMaintenance") &&
      !strcontains(alert.conditions[0].condition_matched_log[0].filter, "instance/uptime") &&
      !strcontains(alert.conditions[0].condition_matched_log[0].filter, "instances.reset") &&
      !strcontains(alert.conditions[0].condition_matched_log[0].filter, "instances.delete") &&
      alert.alert_strategy[0].notification_rate_limit[0].period == "300s" &&
      length(alert.notification_channels) == 1
    ])
    error_message = "GCP lifecycle policies must use narrow managed-ID log filters, rate-limit notifications, and exclude uptime, reset, and delete signals."
  }
}

run "gcp_lifecycle_disabled" {
  command = plan

  module {
    source = "./modules/gcp_monitoring"
  }

  variables {
    resource_prefix = "oilscope-test"
    monitoring = {
      enabled            = true
      notification_email = "alerts@example.com"
      cpu                = { enabled = false, threshold_percent = 80, duration_minutes = 5 }
      lifecycle          = { enabled = false, notify_states = ["stopped"] }
    }
    vms = {
      history = { name = "oilscope-test-history", instance_id = "1111111111111111111" }
    }
  }

  assert {
    condition = (
      length(google_monitoring_alert_policy.lifecycle) == 0 &&
      length(google_monitoring_notification_channel.email) == 0
    )
    error_message = "Disabled GCP lifecycle monitoring must create no lifecycle resources."
  }
}

run "gcp_monitoring_disabled_with_lifecycle" {
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
      lifecycle          = { enabled = true, notify_states = ["stopped", "terminated"] }
    }
    vms = {
      history = { name = "oilscope-test-history", instance_id = "1111111111111111111" }
    }
  }

  assert {
    condition = (
      length(google_monitoring_alert_policy.cpu) == 0 &&
      length(google_monitoring_alert_policy.lifecycle) == 0 &&
      length(google_monitoring_notification_channel.email) == 0
    )
    error_message = "Globally disabled GCP monitoring must suppress CPU and lifecycle resources."
  }
}

run "gcp_vm_health_has_no_unsafe_native_alert" {
  command = plan

  module {
    source = "./modules/gcp_monitoring"
  }

  variables {
    resource_prefix = "oilscope-test"
    monitoring = {
      enabled            = true
      notification_email = "alerts@example.com"
      cpu                = { enabled = false, threshold_percent = 80, duration_minutes = 5 }
      vm_health          = { enabled = true }
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
    error_message = "GCP vm_health alone must not create an unsafe uptime-absence policy or duplicate notification resources."
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
      aws_sns_topic_subscription.email[0].endpoint == var.monitoring.notification_email &&
      toset(keys(aws_cloudwatch_metric_alarm.cpu)) == toset(["history", "fetcher"]) &&
      length(aws_cloudwatch_metric_alarm.vm_health) == 0 &&
      length(aws_cloudwatch_event_rule.lifecycle) == 0 &&
      length(aws_cloudwatch_event_target.lifecycle_sns) == 0 &&
      length(aws_sns_topic_policy.monitoring) == 0
    )
    error_message = "A missing vm_health block must preserve CPU monitoring without health alarms."
  }

  assert {
    condition = alltrue([
      for name, alarm in aws_cloudwatch_metric_alarm.cpu :
      alarm.threshold == 80 &&
      alarm.evaluation_periods == 5 &&
      alarm.dimensions.InstanceId == var.vms[name].instance_id &&
      length(alarm.alarm_actions) == 1
    ])
    error_message = "AWS alarms must propagate the common threshold/duration, use managed instance IDs, and notify the configured SNS topic."
  }

  assert {
    condition = alltrue([
      for vm in values(var.vms) : strcontains(aws_cloudwatch_dashboard.cpu[0].dashboard_body, vm.instance_id)
    ])
    error_message = "The AWS dashboard must select the instance IDs supplied by the managed VM module."
  }
}

run "aws_custom_cpu_threshold" {
  command = plan

  module {
    source = "./modules/aws_monitoring"
  }

  variables {
    resource_prefix = "oilscope-test"
    monitoring = {
      enabled            = true
      notification_email = "alerts@example.com"
      cpu                = { enabled = true, threshold_percent = 20, duration_minutes = 3 }
    }
    vms = {
      history = { name = "oilscope-test-history", instance_id = "i-0123456789abcdef0" }
    }
    tags = {}
  }

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.cpu["history"].threshold == 20 &&
      aws_cloudwatch_metric_alarm.cpu["history"].period == 60 &&
      aws_cloudwatch_metric_alarm.cpu["history"].evaluation_periods == 3 &&
      length(aws_cloudwatch_dashboard.cpu) == 1
    )
    error_message = "A custom AWS CPU threshold and duration must update the stable per-VM alarm while retaining the dashboard."
  }
}

run "aws_lifecycle_monitoring" {
  command = apply

  module {
    source = "./modules/aws_monitoring"
  }

  override_resource {
    target = aws_sns_topic.monitoring
    values = {
      arn = "arn:aws:sns:eu-central-1:123456789012:oilscope-test-monitoring"
    }
  }

  override_resource {
    target = aws_cloudwatch_event_rule.lifecycle
    values = {
      arn = "arn:aws:events:eu-central-1:123456789012:rule/oilscope-test-vm-lifecycle"
    }
  }

  variables {
    resource_prefix = "oilscope-test"
    monitoring = {
      enabled            = true
      notification_email = "alerts@example.com"
      cpu                = { enabled = false, threshold_percent = 80, duration_minutes = 5 }
      lifecycle = {
        enabled       = true
        notify_states = ["stopped", "terminated"]
      }
    }
    vms = {
      history = { name = "oilscope-test-history", instance_id = "i-0123456789abcdef0" }
      fetcher = { name = "oilscope-test-fetcher", instance_id = "i-0fedcba9876543210" }
    }
    tags = { managed_by = "terraform" }
  }

  assert {
    condition = (
      length(aws_cloudwatch_event_rule.lifecycle) == 1 &&
      length(aws_cloudwatch_event_target.lifecycle_sns) == 1 &&
      length(aws_sns_topic_policy.monitoring) == 1 &&
      length(aws_sns_topic.monitoring) == 1 &&
      length(aws_sns_topic_subscription.email) == 1
    )
    error_message = "AWS lifecycle monitoring must create one EventBridge rule/target and reuse one SNS notification path."
  }

  assert {
    condition = (
      jsondecode(aws_cloudwatch_event_rule.lifecycle[0].event_pattern).source == ["aws.ec2"] &&
      jsondecode(aws_cloudwatch_event_rule.lifecycle[0].event_pattern)["detail-type"] == ["EC2 Instance State-change Notification"] &&
      toset(jsondecode(aws_cloudwatch_event_rule.lifecycle[0].event_pattern).detail.state) == toset(["stopped", "terminated"]) &&
      toset(jsondecode(aws_cloudwatch_event_rule.lifecycle[0].event_pattern).detail["instance-id"]) == toset([for vm in values(var.vms) : vm.instance_id])
    )
    error_message = "The AWS event pattern must match only stopped/terminated state changes for supplied managed instance IDs."
  }

  assert {
    condition = (
      aws_cloudwatch_event_target.lifecycle_sns[0].arn == aws_sns_topic.monitoring[0].arn &&
      jsondecode(aws_sns_topic_policy.monitoring[0].policy).Statement[0].Principal.Service == "events.amazonaws.com" &&
      jsondecode(aws_sns_topic_policy.monitoring[0].policy).Statement[0].Action == "sns:Publish" &&
      jsondecode(aws_sns_topic_policy.monitoring[0].policy).Statement[0].Resource == aws_sns_topic.monitoring[0].arn &&
      jsondecode(aws_sns_topic_policy.monitoring[0].policy).Statement[0].Condition.ArnEquals["aws:SourceArn"] == aws_cloudwatch_event_rule.lifecycle[0].arn
    )
    error_message = "EventBridge must target the existing SNS topic through a rule-scoped publish policy."
  }
}

run "aws_lifecycle_disabled" {
  command = plan

  module {
    source = "./modules/aws_monitoring"
  }

  variables {
    resource_prefix = "oilscope-test"
    monitoring = {
      enabled            = true
      notification_email = "alerts@example.com"
      cpu                = { enabled = false, threshold_percent = 80, duration_minutes = 5 }
      lifecycle          = { enabled = false, notify_states = ["stopped"] }
    }
    vms = {
      history = { name = "oilscope-test-history", instance_id = "i-0123456789abcdef0" }
    }
    tags = {}
  }

  assert {
    condition = (
      length(aws_cloudwatch_event_rule.lifecycle) == 0 &&
      length(aws_cloudwatch_event_target.lifecycle_sns) == 0 &&
      length(aws_sns_topic_policy.monitoring) == 0 &&
      length(aws_sns_topic.monitoring) == 0
    )
    error_message = "Disabled AWS lifecycle monitoring must create no lifecycle or notification resources."
  }
}

run "aws_vm_health_monitoring" {
  command = apply

  module {
    source = "./modules/aws_monitoring"
  }

  override_resource {
    target = aws_sns_topic.monitoring
    values = {
      arn = "arn:aws:sns:eu-central-1:123456789012:oilscope-test-monitoring"
    }
  }

  variables {
    resource_prefix = "oilscope-test"
    monitoring = {
      enabled            = true
      notification_email = "alerts@example.com"
      cpu                = { enabled = false, threshold_percent = 80, duration_minutes = 5 }
      vm_health          = { enabled = true }
    }
    vms = {
      history = { name = "oilscope-test-history", instance_id = "i-0123456789abcdef0" }
      fetcher = { name = "oilscope-test-fetcher", instance_id = "i-0fedcba9876543210" }
    }
    tags = { managed_by = "terraform" }
  }

  assert {
    condition = (
      length(aws_sns_topic.monitoring) == 1 &&
      length(aws_sns_topic_subscription.email) == 1 &&
      length(aws_cloudwatch_dashboard.cpu) == 1 &&
      length(aws_cloudwatch_metric_alarm.cpu) == 0 &&
      toset(keys(aws_cloudwatch_metric_alarm.vm_health)) == toset(["history", "fetcher"])
    )
    error_message = "AWS vm_health must create one status-check alarm per Terraform-managed VM and reuse one notification path."
  }

  assert {
    condition = alltrue([
      for name, alarm in aws_cloudwatch_metric_alarm.vm_health :
      alarm.namespace == "AWS/EC2" &&
      alarm.metric_name == "StatusCheckFailed" &&
      alarm.statistic == "Maximum" &&
      alarm.threshold == 1 &&
      alarm.comparison_operator == "GreaterThanOrEqualToThreshold" &&
      alarm.treat_missing_data == "missing" &&
      alarm.dimensions.InstanceId == var.vms[name].instance_id &&
      toset(alarm.alarm_actions) == toset([aws_sns_topic.monitoring[0].arn])
    ])
    error_message = "AWS health alarms must detect native status-check impairment, preserve missing data, reuse SNS, and use managed IDs."
  }

  assert {
    condition = alltrue([
      for vm in values(var.vms) :
      strcontains(aws_cloudwatch_dashboard.cpu[0].dashboard_body, "StatusCheckFailed") &&
      strcontains(aws_cloudwatch_dashboard.cpu[0].dashboard_body, vm.instance_id)
    ])
    error_message = "The existing AWS dashboard must include status checks for every supplied managed instance ID."
  }
}

run "aws_vm_health_disabled" {
  command = plan

  module {
    source = "./modules/aws_monitoring"
  }

  variables {
    resource_prefix = "oilscope-test"
    monitoring = {
      enabled            = true
      notification_email = "alerts@example.com"
      cpu                = { enabled = false, threshold_percent = 80, duration_minutes = 5 }
      vm_health          = { enabled = false }
    }
    vms = {
      history = { name = "oilscope-test-history", instance_id = "i-0123456789abcdef0" }
    }
    tags = {}
  }

  assert {
    condition = (
      length(aws_cloudwatch_metric_alarm.vm_health) == 0 &&
      length(aws_sns_topic.monitoring) == 0 &&
      length(aws_sns_topic_subscription.email) == 0 &&
      length(aws_cloudwatch_dashboard.cpu) == 0
    )
    error_message = "Explicitly disabled vm_health with CPU disabled must create no AWS monitoring resources."
  }
}

run "aws_monitoring_disabled_with_vm_health" {
  command = plan

  module {
    source = "./modules/aws_monitoring"
  }

  variables {
    resource_prefix = "oilscope-test"
    monitoring = {
      enabled            = false
      notification_email = "alerts@example.com"
      cpu                = { enabled = true, threshold_percent = 80, duration_minutes = 5 }
      vm_health          = { enabled = true }
      lifecycle          = { enabled = true, notify_states = ["stopped", "terminated"] }
    }
    vms = {
      history = { name = "oilscope-test-history", instance_id = "i-0123456789abcdef0" }
    }
    tags = {}
  }

  assert {
    condition = (
      length(aws_cloudwatch_metric_alarm.cpu) == 0 &&
      length(aws_cloudwatch_metric_alarm.vm_health) == 0 &&
      length(aws_cloudwatch_event_rule.lifecycle) == 0 &&
      length(aws_cloudwatch_event_target.lifecycle_sns) == 0 &&
      length(aws_sns_topic_policy.monitoring) == 0 &&
      length(aws_sns_topic.monitoring) == 0 &&
      length(aws_sns_topic_subscription.email) == 0 &&
      length(aws_cloudwatch_dashboard.cpu) == 0
    )
    error_message = "Globally disabled monitoring must suppress CPU and health resources."
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
      length(aws_cloudwatch_metric_alarm.cpu) == 0 &&
      length(aws_cloudwatch_metric_alarm.vm_health) == 0 &&
      length(aws_cloudwatch_event_rule.lifecycle) == 0 &&
      length(aws_cloudwatch_event_target.lifecycle_sns) == 0 &&
      length(aws_sns_topic_policy.monitoring) == 0
    )
    error_message = "AWS monitoring with no AWS VMs must create no resources."
  }
}
