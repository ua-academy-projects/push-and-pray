mock_provider "google" {}

variables {
  config = jsondecode(file("../../project-config.example.json"))
  service_account_emails = {
    bastion = "bastion@example-project-12345.iam.gserviceaccount.com"
    ui      = "ui@example-project-12345.iam.gserviceaccount.com"
  }
  vms = {
    bastion = {
      name = "oilscope-dev-bastion"
      role = "bastion"
    }
    ui = {
      name = "oilscope-dev-ui"
      role = "ui"
    }
  }
}

run "grants_agent_roles_and_configures_retention" {
  command = plan

  module {
    source = "./modules/gcp_monitoring"
  }

  assert {
    condition = (
      google_logging_project_bucket_config.default.bucket_id == "_Default" &&
      google_logging_project_bucket_config.default.retention_days == 7
    )
    error_message = "Cloud Logging must use the default bucket and configured retention."
  }

  assert {
    condition     = length(google_project_iam_member.agents) == 4
    error_message = "Each VM service account must receive log writer and metric writer roles."
  }

  assert {
    condition = (
      length(google_monitoring_uptime_check_config.ui) == 1 &&
      length(google_monitoring_alert_policy.system) == 5
    )
    error_message = "Monitoring must configure UI availability plus VM and database alerts."
  }
}
