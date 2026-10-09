resource "google_project_service" "container" {
  count = local.enabled ? 1 : 0

  project            = local.project_id
  service            = "container.googleapis.com"
  disable_on_destroy = false
}

resource "google_container_cluster" "main" {
  count = local.enabled ? 1 : 0

  name     = local.cluster_name
  location = local.zone

  network    = var.network_id
  subnetwork = var.workload_subnet_id

  deletion_protection      = false
  remove_default_node_pool = true
  initial_node_count       = 1
  networking_mode          = "VPC_NATIVE"

  resource_labels = local.merged_common_labels

  release_channel {
    channel = "REGULAR"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = local.master_ipv4_cidr_block
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.authorized_cidrs

      content {
        cidr_block   = cidr_blocks.value
        display_name = "operator-${cidr_blocks.key}"
      }
    }
  }

  depends_on = [google_project_service.container]
}

resource "google_container_node_pool" "main" {
  count = local.enabled ? 1 : 0

  name       = "${local.resource_prefix}-nodes"
  location   = local.zone
  cluster    = google_container_cluster.main[0].name
  node_count = local.node_count

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type    = local.node_machine_type
    disk_size_gb    = 50
    disk_type       = "pd-balanced"
    service_account = google_service_account.nodes[0].email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    tags            = [var.network_tags.gke_node]
    labels          = local.merged_common_labels

    metadata = {
      disable-legacy-endpoints = "true"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  depends_on = [google_project_iam_member.nodes]
}
