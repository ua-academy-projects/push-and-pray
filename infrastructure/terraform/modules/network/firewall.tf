resource "google_compute_firewall" "bastion_ssh" {
  name    = "${var.resource_prefix}-allow-bastion-ssh"
  network = google_compute_network.main.id

  source_ranges = var.bastion_allowed_cidrs
  target_tags   = [local.network_tags.bastion]

  allow {
    protocol = "tcp"
    ports = sort(distinct([
      "22",
      tostring(var.bastion_ssh_port),
    ]))
  }
}

# The rule has no public CIDR source: only instances carrying the bastion tag
# can initiate workload SSH. The custom VPC also has no default-allow rules.
#trivy:ignore:AVD-GCP-0071
#trivy:ignore:AVD-GCP-0073
resource "google_compute_firewall" "workload_ssh" {
  name    = "${var.resource_prefix}-allow-workload-ssh"
  network = google_compute_network.main.id

  source_tags = [local.network_tags.bastion]
  target_tags = [
    local.network_tags.infra,
    local.network_tags.history,
    local.network_tags.fetcher,
    local.network_tags.ui,
  ]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "ui_web" {
  name    = "${var.resource_prefix}-allow-ui-web"
  network = google_compute_network.main.id

  source_ranges = ["0.0.0.0/0"]
  target_tags   = [local.network_tags.ui]

  allow {
    protocol = "tcp"
    ports    = var.ui_public_ports
  }
}

resource "google_compute_firewall" "history_api" {
  name    = "${var.resource_prefix}-allow-history-api"
  network = google_compute_network.main.id

  source_tags = [local.network_tags.ui]
  target_tags = [local.network_tags.history]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.history_api_port)]
  }
}

resource "google_compute_firewall" "postgresql" {
  name    = "${var.resource_prefix}-allow-postgresql"
  network = google_compute_network.main.id

  source_tags = [
    local.network_tags.fetcher,
    local.network_tags.history,
    local.network_tags.ui,
  ]

  target_tags = [local.network_tags.infra]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.postgresql_port)]
  }
}
