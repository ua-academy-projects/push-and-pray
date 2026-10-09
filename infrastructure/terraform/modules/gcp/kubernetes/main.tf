locals {
  name       = "${var.config.name_prefix}-${var.config.environment}-gke"
  project_id = var.config.clouds.gcp.project_id
  location   = var.config.locations[var.config.default_location].gcp.zone
  node_size  = try(var.config.kubernetes.node_size, "medium")
  node_count = try(var.config.kubernetes.node_count, 3)
  labels     = merge(var.config.common_labels, { environment = var.config.environment })
}

resource "google_project_service" "container" {
  project            = local.project_id
  service            = "container.googleapis.com"
  disable_on_destroy = false
}

resource "google_service_account" "nodes" {
  project      = local.project_id
  account_id   = "${substr(var.config.name_prefix, 0, 16)}-${var.config.environment}-gke"
  display_name = "OilScope GKE nodes"
}

resource "google_project_iam_member" "node_metrics" {
  for_each = toset(["roles/logging.logWriter", "roles/monitoring.metricWriter"])
  project  = local.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_container_cluster" "main" {
  project                  = local.project_id
  name                     = local.name
  location                 = local.location
  network                  = var.network_id
  subnetwork               = var.subnet_id
  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = var.config.environment == "prod"
  resource_labels          = local.labels

  ip_allocation_policy {}

  addons_config {
    gce_persistent_disk_csi_driver_config { enabled = true }
  }

  release_channel { channel = "REGULAR" }

  depends_on = [google_project_service.container]
}

resource "google_container_node_pool" "main" {
  project    = local.project_id
  name       = "${local.name}-nodes"
  location   = local.location
  cluster    = google_container_cluster.main.name
  node_count = local.node_count

  node_config {
    machine_type    = var.config.provider_mappings.instance_types[local.node_size].gcp.machine_type
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    labels          = local.labels
  }

  depends_on = [google_project_iam_member.node_metrics]
}
