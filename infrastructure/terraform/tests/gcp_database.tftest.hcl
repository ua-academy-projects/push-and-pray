mock_provider "google" {}
mock_provider "random" {}

variables {
  config             = jsondecode(file("../../project-config.example.json"))
  network_id         = "projects/example-project-12345/global/networks/oilscope-dev-vpc"
  password_secret_id = "projects/example-project-12345/secrets/example-db-password"
}

run "private_cloud_sql_postgresql" {
  command = plan

  module {
    source = "./modules/gcp_database"
  }

  assert {
    condition = (
      google_sql_database_instance.main.settings[0].ip_configuration[0].ipv4_enabled == false &&
      google_sql_database_instance.main.deletion_protection == false
    )
    error_message = "Development Cloud SQL must use only its private connection and remain destroyable."
  }

  assert {
    condition     = google_sql_database.application.name == var.config.services.database.name
    error_message = "Cloud SQL must create the configured application database."
  }
}
