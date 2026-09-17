mock_provider "aws" {
  mock_data "aws_ami" {
    defaults = {
      id = "ami-0123456789abcdef0"
    }
  }
}
mock_provider "archive" {}
mock_provider "cloudflare" {}

run "aws_profile_uses_only_aws_root" {
  command = plan

  variables {
    project_config_path = "../../../../configs/project-config.aws.json"
    database_password   = "test-only-password"
    cloudflare_zone_id  = "0123456789abcdef0123456789abcdef"
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
      output.deployment.dns.hostname == "shiphappens.pp.ua" &&
      output.deployment.nodes.ui.role == "ui"
    )
    error_message = "The AWS root must expose the normalized deployment contract."
  }
}

run "aws_portable_profile" {
  command = plan

  variables {
    project_config_path = "../../../../configs/project-config.aws-portable.json"
    cloudflare_zone_id  = "0123456789abcdef0123456789abcdef"
  }

  assert {
    condition = (
      length(output.vms) == 5 &&
      output.deployment.data_profile == "portable" &&
      output.deployment.database.mode == "portable" &&
      output.vms.infra.role == "database" &&
      output.vms.infra.private_address == "10.0.1.4" &&
      output.vms.ui.private_address == "10.0.2.7"
    )
    error_message = "The AWS portable profile must use a private database VM and a UI address in the public subnet."
  }
}
