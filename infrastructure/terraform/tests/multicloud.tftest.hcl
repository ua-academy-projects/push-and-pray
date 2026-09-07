mock_provider "google" {}
mock_provider "aws" {}

run "invalid_duplicate_role" {
  command = plan
  variables { project_config_path = ".terraform/test-configs/invalid-role-duplicate.json" }
  expect_failures = [terraform_data.configuration_validation]
}

run "invalid_public_ip" {
  command = plan
  variables { project_config_path = ".terraform/test-configs/invalid-public-ip.json" }
  expect_failures = [terraform_data.configuration_validation]
}

run "invalid_reserved_label" {
  command = plan
  variables { project_config_path = ".terraform/test-configs/invalid-reserved-label.json" }
  expect_failures = [terraform_data.configuration_validation]
}

run "invalid_provider_declaration" {
  command = plan
  variables { project_config_path = ".terraform/test-configs/invalid-provider-declaration.json" }
  expect_failures = [terraform_data.configuration_validation]
}

run "per_vm_region_override" {
  command = plan
  variables { project_config_path = ".terraform/test-configs/region-override.json" }
  assert {
    condition = (
      output.resolved_vm_configuration.history.logical_region == "alias" &&
      output.resolved_vm_configuration.fetcher.logical_region == "europe" &&
      output.resolved_vm_configuration.history.provider_zone == output.resolved_vm_configuration.fetcher.provider_zone
    )
    error_message = "Per-VM logical region overrides must preserve default inheritance for other VMs."
  }
}

variables {
  secret_version_managers = []
}

run "preserve_secret_version_writers" {
  command = plan

  variables {
    project_config_path     = "../../project-config.example.json"
    secret_version_managers = ["user:uploader@example.com"]
  }

  assert {
    condition = (
      toset(keys(google_secret_manager_secret_iam_member.version_adder)) ==
      toset([for secret_id in local.gcp_secret_ids : "${secret_id}/user:uploader@example.com"]) &&
      length(google_secret_manager_secret_iam_member.version_adder) > 0 &&
      alltrue([
        for grant in values(google_secret_manager_secret_iam_member.version_adder) :
        grant.role == "roles/secretmanager.secretVersionAdder" && grant.member == "user:uploader@example.com"
      ])
    )
    error_message = "Explicit uploader configuration must retain each secret's version-adder IAM grant."
  }
}

run "gcp_only" {
  command = plan

  variables {
    project_config_path = "../../project-config.example.json"
  }

  assert {
    condition = alltrue([
      for vm in values(output.resolved_vm_configuration) :
      vm.cloud == "gcp"
    ])
    error_message = "The example configuration must resolve every VM to GCP."
  }
}

run "aws_only" {
  command = plan

  variables {
    project_config_path = ".terraform/test-configs/aws-only.json"
  }

  assert {
    condition = alltrue([
      for vm in values(output.resolved_vm_configuration) :
      vm.cloud == "aws" &&
      vm.provider_region == "eu-central-1" &&
      vm.provider_zone == "eu-central-1a"
    ])
    error_message = "AWS-only configuration must resolve every VM to the configured AWS region and zone."
  }

  assert {
    condition = (
      output.resolved_vm_configuration.ui.provider_size == "t3.micro" &&
      output.resolved_vm_configuration.ui.provider_disk_type == "gp3"
    )
    error_message = "AWS-only configuration must use the AWS size and disk mappings."
  }
}

run "hybrid" {
  command = plan

  variables {
    project_config_path = ".terraform/test-configs/hybrid.json"
  }

  assert {
    condition = (
      output.resolved_vm_configuration.ui.cloud == "aws" &&
      output.resolved_vm_configuration.ui.provider_size == "t3.micro" &&
      output.resolved_vm_configuration.ui.provider_disk_type == "gp3" &&
      output.resolved_vm_configuration.infra.role == "database" &&
      output.resolved_vm_configuration.infra.cloud == "gcp" &&
      output.resolved_vm_configuration.infra.provider_region == "europe-west1"
    )
    error_message = "A per-VM cloud override must resolve provider-specific values without changing other VMs."
  }
}

run "invalid_multi_region" {
  command = plan

  variables {
    project_config_path = ".terraform/test-configs/invalid-multi-region.json"
  }

  expect_failures = [terraform_data.configuration_validation]
}

run "invalid_subnet_overlap" {
  command = plan

  variables {
    project_config_path = ".terraform/test-configs/invalid-subnet-overlap.json"
  }

  expect_failures = [terraform_data.configuration_validation]
}
