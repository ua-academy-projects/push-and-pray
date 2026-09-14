mock_provider "google" {}
mock_provider "aws" {}
mock_provider "random" {}

variables {
  secret_version_managers = []
}

run "self_hosted_preserves_existing_database" {
  command = plan
  variables { project_config_path = "../../project-config.example.json" }

  assert {
    condition = (
      output.database_connection.mode == "self_hosted" &&
      length(module.gcp_managed_database) == 0 &&
      length(module.aws_managed_database) == 0 &&
      length(random_password.managed_database) == 0 &&
      random_password.redis.length == 32 &&
      output.redis_connection.port == 6379
    )
    error_message = "Self-hosted mode must create neither managed database nor generated credentials."
  }
}

run "gcp_managed_database_is_private" {
  command = plan
  variables { project_config_path = ".terraform/test-configs/gcp-managed.json" }

  assert {
    condition = (
      output.database_connection.mode == "managed" &&
      output.database_connection.cloud == "gcp" &&
      length(module.gcp_managed_database) == 1 &&
      length(module.aws_managed_database) == 0 &&
      module.gcp_managed_database[0].public_ipv4_enabled == false &&
      module.gcp_managed_database[0].cron_database_name == "oil_tracker" &&
      !contains(output.workload_secret_access.fetcher, "oilscope-dev-database-host") &&
      !contains(output.workload_secret_access.fetcher, "example-db-password") &&
      output.redis_network_policy.gcp.source_ranges == null &&
      toset(output.redis_network_policy.gcp.ports) == toset(["6379"])
    )
    error_message = "GCP managed mode must create private-only Cloud SQL on the workload VPC."
  }
}

run "aws_managed_database_is_private" {
  command = plan
  variables { project_config_path = ".terraform/test-configs/aws-managed.json" }

  assert {
    condition = (
      output.database_connection.mode == "managed" &&
      output.database_connection.cloud == "aws" &&
      length(module.aws_managed_database) == 1 &&
      length(module.gcp_managed_database) == 0 &&
      module.aws_managed_database[0].publicly_accessible == false &&
      module.aws_managed_database[0].database_subnet_count == 2 &&
      length(toset(module.aws_managed_database[0].database_subnet_availability_zones)) == 2 &&
      length(toset(module.aws_managed_database[0].database_subnet_cidrs)) == 2 &&
      toset(module.aws_managed_database[0].database_subnet_cidrs) == toset(["10.0.2.0/24", "10.0.3.0/24"]) &&
      module.aws_managed_database[0].private_route_association_count == 2 &&
      module.aws_managed_database[0].cron_database_name == "oil_tracker" &&
      module.aws_managed_database[0].ingress_rule_count == 2 &&
      !contains(output.workload_secret_access.fetcher, "oilscope-dev-database-host") &&
      !contains(output.workload_secret_access.fetcher, "example-db-password") &&
      output.redis_network_policy.aws.cidr_ipv4 == null &&
      output.redis_network_policy.aws.from_port == 6379 &&
      output.redis_network_policy.aws.to_port == 6379
    )
    error_message = "AWS managed mode must create private RDS with two DB subnets and app-SG-only ingress."
  }
}

run "managed_hybrid_is_rejected" {
  command = plan
  variables { project_config_path = ".terraform/test-configs/hybrid-managed.json" }
  expect_failures = [terraform_data.configuration_validation]
}

run "invalid_database_mode_is_rejected" {
  command = plan
  variables { project_config_path = ".terraform/test-configs/invalid-database-mode.json" }
  expect_failures = [terraform_data.configuration_validation]
}

run "aws_managed_database_subnet_overlap_is_rejected" {
  command = plan
  variables { project_config_path = ".terraform/test-configs/invalid-aws-managed-subnet-overlap.json" }
  expect_failures = [terraform_data.configuration_validation]
}
