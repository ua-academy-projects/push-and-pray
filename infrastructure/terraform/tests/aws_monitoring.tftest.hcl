mock_provider "aws" {}

variables {
  config = merge(jsondecode(file("../../project-config.example.json")), {
    default_cloud = "aws"
  })
  role_names = {
    bastion = "oilscope-dev-bastion-runtime"
    ui      = "oilscope-dev-ui-runtime"
  }
  vms = {
    bastion = {
      instance_id = "i-00000000000000001"
      role        = "bastion"
    }
    ui = {
      instance_id = "i-00000000000000002"
      role        = "ui"
    }
  }
}

run "creates_shared_log_group_and_per_vm_permissions" {
  command = plan

  module {
    source = "./modules/aws_monitoring"
  }

  assert {
    condition = (
      aws_cloudwatch_log_group.journald.name == "/oilscope/dev/journald" &&
      aws_cloudwatch_log_group.journald.retention_in_days == 7
    )
    error_message = "Monitoring must use the environment log group and configured retention."
  }

  assert {
    condition     = toset(keys(aws_iam_role_policy.monitoring)) == toset(["bastion", "ui"])
    error_message = "Every supplied VM role must receive monitoring permissions."
  }

  assert {
    condition = (
      length(aws_route53_health_check.ui) == 1 &&
      length(aws_cloudwatch_metric_alarm.vm) == 6 &&
      aws_cloudwatch_dashboard.main.dashboard_name == "oilscope-dev-overview"
    )
    error_message = "Monitoring must configure UI availability, VM alerts, and the dashboard."
  }
}
