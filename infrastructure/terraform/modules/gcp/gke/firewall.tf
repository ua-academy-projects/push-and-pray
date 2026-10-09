resource "google_compute_firewall" "control_plane_to_nodes" {
  count = local.enabled ? 1 : 0

  name    = "${local.resource_prefix}-allow-gke-control-plane"
  network = var.network_id

  source_ranges = [local.master_ipv4_cidr_block]
  target_tags   = [var.network_tags.gke_node]

  allow {
    protocol = "tcp"
    ports    = ["443", "8443", "9443", "10250"]
  }
}

resource "google_compute_firewall" "bastion_to_nodes" {
  count = local.enabled ? 1 : 0

  name    = "${local.resource_prefix}-allow-gke-from-bastion"
  network = var.network_id

  source_tags = [var.network_tags.bastion]
  target_tags = [var.network_tags.gke_node]

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
}
