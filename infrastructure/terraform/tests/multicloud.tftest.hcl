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
