mock_provider "google" {}
mock_provider "cloudflare" {}

run "gcp_profile_uses_only_gcp_root" {
  command = plan

  variables {
    project_config_path = "../../../../configs/project-config.gcp.json"
    database_password   = "test-only-password"
    cloudflare_zone_id  = "0123456789abcdef0123456789abcdef"
  }

  assert {
    condition     = length(output.vms) == 4 && output.managed_database.cloud == "gcp"
    error_message = "The isolated GCP root must create four GCP VMs and Cloud SQL."
  }

  assert {
    condition = (
      output.deployment.contract_version == 1 &&
      output.deployment.provider == "gcp" &&
      output.deployment.data_profile == "managed" &&
      output.deployment.runtime == "compose" &&
      output.deployment.database.mode == "managed" &&
      output.deployment.dns.hostname == "shiphappens.pp.ua" &&
      output.deployment.nodes.ui.role == "ui"
    )
    error_message = "The GCP root must expose the normalized deployment contract."
  }

  assert {
    condition = (
      length(output.registry.application) == 4 &&
      output.registry.immutable_tags &&
      startswith(output.registry.application.fetcher, "europe-west1-docker.pkg.dev/")
    )
    error_message = "GCP must create an immutable Artifact Registry for every application image."
  }

  assert {
    condition = (
      output.managed_database.security.public_endpoint == false &&
      output.managed_database.security.transport_encrypted == true &&
      output.managed_database.sslmode == "require" &&
      output.deployment.database.sslmode == "require" &&
      output.vms.history.public_address == null &&
      output.vms.fetcher.public_address == null
    )
    error_message = "GCP managed PostgreSQL and workload VMs must remain private, with encrypted database connections required."
  }
}

run "gcp_portable_profile" {
  command = plan

  variables {
    project_config_path = "../../../../configs/project-config.gcp-portable.json"
    cloudflare_zone_id  = "0123456789abcdef0123456789abcdef"
  }

  assert {
    condition = (
      length(output.vms) == 5 &&
      output.deployment.data_profile == "portable" &&
      output.deployment.database.mode == "portable" &&
      output.deployment.database.sslmode == "disable" &&
      output.vms.infra.role == "database" &&
      output.vms.infra.private_address == "10.0.1.4" &&
      output.vms.ui.private_address == "10.0.1.7"
    )
    error_message = "The GCP portable profile must use a private database VM in the workload subnet."
  }
}
