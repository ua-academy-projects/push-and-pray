mock_provider "google" {}

run "postgresql_only_firewall_contract" {
  command = plan

  module {
    source = "./modules/network"
  }

  variables {
    project_id              = "sample-project"
    name_prefix             = "oilscope-test"
    bastion_allowed_cidrs   = ["203.0.113.10/32"]
    postgresql_port         = 5432
    history_api_port        = 8001
    fetcher_health_port     = 8002
    ui_internal_port        = 8080
    ui_public_ports         = ["80", "443"]
    enable_firewall_logging = false
  }

  assert {
    condition = google_compute_firewall.postgresql_to_infra.source_tags == toset([
      "oilscope-test-fetcher",
      "oilscope-test-history",
      "oilscope-test-ui",
    ])
    error_message = "PostgreSQL must be reachable only from Fetcher, History and UI role tags."
  }

  assert {
    condition     = google_compute_firewall.postgresql_to_infra.target_tags == toset(["oilscope-test-infra"])
    error_message = "PostgreSQL must target only the Infra role tag."
  }

  assert {
    condition     = toset(one(google_compute_firewall.postgresql_to_infra.allow).ports) == toset(["5432"])
    error_message = "The PostgreSQL firewall rule must expose only the configured PostgreSQL port."
  }

  assert {
    condition     = google_compute_firewall.history_api_from_ui.source_tags == toset(["oilscope-test-ui"])
    error_message = "History API access must originate only from the UI role tag."
  }

  assert {
    condition     = google_compute_firewall.history_api_from_ui.target_tags == toset(["oilscope-test-history"])
    error_message = "History API access must target only the History role tag."
  }

  assert {
    condition     = google_compute_firewall.ssh_from_bastion.source_tags == toset(["oilscope-test-bastion"])
    error_message = "Workload SSH access must originate only from the Bastion role tag."
  }

  assert {
    condition = toset(one(google_compute_firewall.ui_public_ingress[0].allow).ports) == toset([
      "80",
      "443",
    ])
    error_message = "The public UI firewall rule must expose exactly ports 80 and 443."
  }
}

run "reject_postgresql_as_public_ui_port" {
  command = plan

  module {
    source = "./modules/network"
  }

  variables {
    project_id            = "sample-project"
    bastion_allowed_cidrs = ["203.0.113.10/32"]
    ui_public_ports       = ["80", "443", "5432"]
  }

  expect_failures = [var.ui_public_ports]
}

run "reject_history_api_as_public_ui_port" {
  command = plan

  module {
    source = "./modules/network"
  }

  variables {
    project_id            = "sample-project"
    bastion_allowed_cidrs = ["203.0.113.10/32"]
    ui_public_ports       = ["80", "443", "8001"]
  }

  expect_failures = [var.ui_public_ports]
}

run "reject_fetcher_health_as_public_ui_port" {
  command = plan

  module {
    source = "./modules/network"
  }

  variables {
    project_id            = "sample-project"
    bastion_allowed_cidrs = ["203.0.113.10/32"]
    ui_public_ports       = ["80", "443", "8002"]
  }

  expect_failures = [var.ui_public_ports]
}

run "reject_ui_internal_as_public_ui_port" {
  command = plan

  module {
    source = "./modules/network"
  }

  variables {
    project_id            = "sample-project"
    bastion_allowed_cidrs = ["203.0.113.10/32"]
    ui_public_ports       = ["80", "443", "8080"]
  }

  expect_failures = [var.ui_public_ports]
}
