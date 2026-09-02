mock_provider "google" {}
mock_provider "aws" {}

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
