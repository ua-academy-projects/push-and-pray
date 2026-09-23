mock_provider "aws" {}

variables {
  config = merge(jsondecode(file("../../project-config.example.json")), {
    default_cloud = "aws"
  })
  role_names = {
    bastion = "oilscope-dev-bastion-runtime"
    ui      = "oilscope-dev-ui-runtime"
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
}
