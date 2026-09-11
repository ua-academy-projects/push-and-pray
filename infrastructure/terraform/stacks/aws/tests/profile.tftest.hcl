mock_provider "aws" {}
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
}
