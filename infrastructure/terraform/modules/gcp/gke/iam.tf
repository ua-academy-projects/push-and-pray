resource "google_service_account" "nodes" {
  count = local.enabled ? 1 : 0

  account_id   = "${local.resource_prefix}-gke-nodes"
  display_name = "${local.resource_prefix}-gke-nodes"
  description  = "Runtime identity for GKE worker nodes"
}

resource "google_project_iam_member" "nodes" {
  for_each = local.enabled ? toset(local.node_roles) : toset([])

  project = local.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes[0].email}"
}
