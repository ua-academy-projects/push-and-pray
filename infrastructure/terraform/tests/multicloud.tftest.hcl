mock_provider "aws" {}
mock_provider "google" {}

run "gcp_default_selects_only_gcp" {
  command = plan

  variables {
    project_config_path = "../../project-config.example.json"
  }

  assert {
    condition     = output.default_cloud == "gcp"
    error_message = "The default GCP example must report gcp."
  }

  assert {
    condition     = length(module.gcp.vms) == 5 && length(module.aws.vms) == 0
    error_message = "GCP default must select five GCP VMs and zero AWS VMs."
  }
}

run "per_vm_override_selects_both_clouds" {
  command = plan

  variables {
    project_config_path = "tests/fixtures/mixed.json"
  }

  assert {
    condition = (
      length(module.gcp.vms) == 4 &&
      length(module.aws.vms) == 1 &&
      module.aws.vms["history"].cloud == "aws" &&
      !contains(keys(module.gcp.vms), "history")
    )
    error_message = "The history override must move only that VM from GCP to AWS."
  }
}

run "unknown_profile_is_rejected" {
  command = plan

  variables {
    project_config_path = "tests/fixtures/invalid-profile.json"
  }

  expect_failures = [
    output.vms,
  ]
}

run "aws_managed_database_profile" {
  command = plan

  variables {
    project_config_path = "../../configs/project-config.aws.json"
    database_password   = "test-only-password"
  }

  assert {
    condition = (
      length(module.aws.vms) == 4 &&
      length(module.gcp.vms) == 0 &&
      module.aws.managed_database.enabled &&
      module.aws.managed_database.cloud == "aws"
    )
    error_message = "The AWS profile must create four VMs and a private RDS database."
  }
}

run "gcp_managed_database_profile" {
  command = plan

  variables {
    project_config_path = "../../configs/project-config.gcp.json"
    database_password   = "test-only-password"
  }

  assert {
    condition = (
      length(module.gcp.vms) == 4 &&
      length(module.aws.vms) == 0 &&
      module.gcp.managed_database.enabled &&
      module.gcp.managed_database.cloud == "gcp"
    )
    error_message = "The GCP profile must create four VMs and a private Cloud SQL database."
  }
}

run "mixed_private_vpn_profile" {
  command = plan

  variables {
    project_config_path = "../../configs/project-config.mixed.json"
    database_password   = "test-only-password"
  }

  assert {
    condition = (
      length(module.aws.vms) == 3 &&
      length(module.gcp.vms) == 2 &&
      length(aws_vpn_connection.mixed) == 1 &&
      length(google_compute_vpn_tunnel.aws) == 1 &&
      module.gcp.managed_database.cloud == "gcp"
    )
    error_message = "The mixed profile must create both cloud groups, a private VPN, and Cloud SQL."
  }
}
