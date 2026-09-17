mock_provider "aws" {
  mock_data "aws_ami" {
    defaults = {
      id = "ami-0123456789abcdef0"
    }
  }
}
mock_provider "archive" {}

run "aws_profile_uses_only_aws_root" {
  command = plan

  variables {
    project_config_path = "../../../../configs/project-config.aws.json"
    database_password   = "test-only-password"
  }

  assert {
    condition     = length(output.vms) == 4 && output.managed_database.cloud == "aws"
    error_message = "The isolated AWS root must create four AWS VMs and RDS."
  }

  assert {
    condition = (
      output.deployment.contract_version == 1 &&
      output.deployment.provider == "aws" &&
      output.deployment.data_profile == "managed" &&
      output.deployment.runtime == "compose" &&
      output.deployment.database.mode == "managed" &&
      output.deployment.nodes.ui.role == "ui"
    )
    error_message = "The AWS root must expose the normalized deployment contract."
  }
}
