run "resolve_gcp_profiles" {
  command = plan

  module {
    source = "./modules/config"
  }

  variables {
    project_config_path = "../../project-config.example.json"
    cloud               = "gcp"
  }

  assert {
    condition = (
      output.schema_version == 1 &&
      output.cloud_provider == "gcp" &&
      output.data_profile == "portable" &&
      output.deployment_runtime == "compose" &&
      output.selected_count == 5 &&
      output.resolved_vms["history"].machine_type == "e2-small" &&
      output.resolved_vms["history"].image_profile == "ubuntu" &&
      output.resolved_vms["history"].disk_type == "pd-balanced" &&
      contains(keys(output.resolved_vms["history"].secret_mappings), "POSTGRES_PASSWORD") &&
      !contains(keys(output.resolved_vms["history"].secret_mappings), "GHCR_TOKEN") &&
      length(output.resolved_vms["bastion"].secret_mappings) == 0
    )
    error_message = "The resolver must translate GCP abstract profiles."
  }
}

run "resolve_aws_profiles_and_override" {
  command = plan

  module {
    source = "./modules/config"
  }

  variables {
    project_config_path = "tests/fixtures/mixed.json"
    cloud               = "aws"
  }

  assert {
    condition = (
      output.selected_count == 1 &&
      output.resolved_vms["history"].machine_type == "t3.small" &&
      output.resolved_vms["history"].image == "ami-0123456789abcdef0" &&
      output.resolved_vms["history"].disk_type == "gp3" &&
      output.resolved_vms["history"].internal_ip == "10.0.1.5" &&
      output.resolved_vms["history"].secret_mappings.POSTGRES_PASSWORD == "example-db-password" &&
      output.resolved_vms["history"].metadata.cloud == "aws"
    )
    error_message = "The resolver must select the override and translate AWS profiles."
  }
}

run "unused_cloud_resolves_empty" {
  command = plan

  module {
    source = "./modules/config"
  }

  variables {
    project_config_path = "../../project-config.example.json"
    cloud               = "aws"
  }

  assert {
    condition = (
      output.selected_count == 0 &&
      length(output.provisionable_vms) == 0 &&
      length(output.all_secret_ids) == 0
    )
    error_message = "An unused cloud must resolve to empty collections."
  }
}
