data "google_compute_zones" "available" {
  project = var.config.cloud_settings.gcp.project_id
  region  = local.placement.region
  status  = "UP"
}

resource "google_project_service" "container" {
  project            = var.config.cloud_settings.gcp.project_id
  service            = "container.googleapis.com"
  disable_on_destroy = false
}

resource "google_service_account" "nodes" {
  project      = var.config.cloud_settings.gcp.project_id
  account_id   = "${local.resource_prefix}-gke-nodes"
  display_name = "${local.resource_prefix} GKE nodes"
}

resource "google_project_iam_member" "nodes" {
  project = var.config.cloud_settings.gcp.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_compute_address" "ingress" {
  project = var.config.cloud_settings.gcp.project_id
  name    = "${local.resource_prefix}-kubernetes-ingress"
  region  = local.placement.region
}

resource "google_compute_address" "private_ingress" {
  project      = var.config.cloud_settings.gcp.project_id
  name         = "${local.resource_prefix}-kubernetes-private-ingress"
  region       = local.placement.region
  address_type = "INTERNAL"
  subnetwork   = var.network.private_subnet_id
  address      = local.cluster.private_ingress_ip
}

resource "google_container_cluster" "this" {
  project  = var.config.cloud_settings.gcp.project_id
  name     = "${local.resource_prefix}-kubernetes"
  location = local.placement.region

  network        = var.network.network_id
  subnetwork     = var.network.private_subnet_id
  node_locations = local.worker_zones

  deletion_protection      = false
  remove_default_node_pool = true
  initial_node_count       = 1
  min_master_version       = local.cluster.version
  networking_mode          = "VPC_NATIVE"

  node_config {
    machine_type    = var.config.machine_types[local.cluster.machine_type].gcp
    disk_size_gb    = local.cluster.disk_size_gb
    disk_type       = var.config.disk_types.general_purpose.gcp.type
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    metadata = {
      disable-legacy-endpoints = "true"
    }

    shielded_instance_config {
      enable_integrity_monitoring = true
      enable_secure_boot          = true
    }
  }

  ip_allocation_policy {
    cluster_ipv4_cidr_block  = var.config.k3s.cluster_cidr
    services_ipv4_cidr_block = var.config.k3s.service_cidr
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = toset(var.config.bastion.allowed_cidrs)
      content {
        cidr_block   = cidr_blocks.value
        display_name = "operator-${replace(replace(cidr_blocks.value, ".", "-"), "/", "-")}"
      }
    }
  }

  workload_identity_config {
    workload_pool = "${var.config.cloud_settings.gcp.project_id}.svc.id.goog"
  }

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  resource_labels = local.labels

  lifecycle {
    # GKE requires a default pool while creating a Standard cluster, then
    # remove_default_node_pool deletes it. These settings configure only that
    # disposable pool; ignoring later drift prevents control-plane updates
    # from trying to modify the now-absent "default-pool".
    ignore_changes = [
      initial_node_count,
      node_config,
      node_locations,
    ]
  }

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }

  depends_on = [
    google_project_service.container,
    google_project_iam_member.nodes,
  ]
}

resource "google_container_node_pool" "application" {
  project            = var.config.cloud_settings.gcp.project_id
  name               = "${local.resource_prefix}-application"
  location           = local.placement.region
  node_locations     = local.worker_zones
  cluster            = google_container_cluster.this.name
  initial_node_count = 1

  autoscaling {
    total_min_node_count = local.cluster.node_count
    total_max_node_count = local.cluster.node_count
    location_policy      = "BALANCED"
  }

  node_config {
    machine_type    = var.config.machine_types[local.cluster.machine_type].gcp
    disk_size_gb    = local.cluster.disk_size_gb
    disk_type       = var.config.disk_types.general_purpose.gcp.type
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    labels          = { "oilscope.io/role" = "agent" }
    tags            = ["${local.resource_prefix}-${var.config.default_location}-kubernetes-node"]

    metadata = {
      disable-legacy-endpoints = "true"
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_integrity_monitoring = true
      enable_secure_boot          = true
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  depends_on = [google_project_iam_member.nodes]
}
