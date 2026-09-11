mock_provider "google" {}

run "gcp_profile_uses_only_gcp_root" {
  command = plan

  variables {
    project_config_path = "../../../../configs/project-config.gcp.json"
    database_password   = "test-only-password"
  }

  assert {
    condition     = length(output.vms) == 4 && output.managed_database.cloud == "gcp"
    error_message = "The isolated GCP root must create four GCP VMs and Cloud SQL."
  }
}
