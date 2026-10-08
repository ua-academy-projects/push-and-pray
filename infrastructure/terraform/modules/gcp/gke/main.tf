locals {
  cluster_name = "${var.resource_prefix}-gke"
}

# These APIs are prerequisites for GKE, the VPC-native node pool, and the
# Artifact Registry/Secret Manager integrations used by the platform.
resource "google_project_service" "required" {
  for_each = toset([
    "artifactregistry.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "secretmanager.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_compute_global_address" "ingress" {
  project      = var.project_id
  name         = "${local.cluster_name}-ingress"
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
  labels       = var.labels

  depends_on = [google_project_service.required]
}

resource "google_service_account" "node" {
  project      = var.project_id
  account_id   = "${var.resource_prefix}-gke-node"
  display_name = "GKE node service account"
}

resource "google_project_iam_member" "node" {
  for_each = toset([
    "roles/artifactregistry.reader",
    "roles/container.defaultNodeServiceAccount",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.node.email}"
}

resource "google_container_cluster" "this" {
  project                  = var.project_id
  name                     = local.cluster_name
  location                 = var.location
  network                  = var.network_id
  subnetwork               = var.subnetwork_name
  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = false
  resource_labels          = var.labels

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # GKE must create one initial node pool before Terraform removes it. Give
  # that short-lived pool the same explicitly managed identity as the actual
  # worker pool; otherwise GKE falls back to the project Compute Engine
  # default service account, which frequently has no node permissions.
  node_config {
    service_account = google_service_account.node.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  depends_on = [google_project_service.required, google_project_iam_member.node]
}

resource "google_container_node_pool" "workers" {
  project            = var.project_id
  name               = "${local.cluster_name}-workers"
  location           = google_container_cluster.this.location
  cluster            = google_container_cluster.this.name
  initial_node_count = 3

  autoscaling {
    min_node_count = 3
    max_node_count = 3
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type    = var.settings.node_machine_type
    disk_type       = "pd-balanced"
    disk_size_gb    = 50
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    labels          = var.labels
    service_account = google_service_account.node.email

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  depends_on = [google_project_iam_member.node]
}
