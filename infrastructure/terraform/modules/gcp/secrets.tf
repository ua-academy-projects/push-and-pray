locals {
  secret_ids = module.selection.secret_ids

  # Only k3s_server nodes read secrets. Ansible resolves them there and hands
  # them on in memory: the join token to the agents, the Tailscale key to the
  # bastions, the rest into Kubernetes Secrets.
  server_nodes = [for name, node in local.nodes : name if node.role == "k3s_server"]

  server_secret_pairs = {
    for pair in setproduct(local.server_nodes, local.secret_ids) :
    "${pair[0]}/${pair[1]}" => {
      node_name = pair[0]
      secret_id = pair[1]
    }
  }

  # Identities allowed to write a new version but never read one. They come from
  # this cloud's profile, because each provider names a principal its own way.
  secret_version_writers = {
    for pair in setproduct(local.secret_ids, try(local.profile.secret_version_managers, [])) :
    "${pair[0]}/${pair[1]}" => {
      secret_id = pair[0]
      member    = pair[1]
    }
  }
}

resource "google_secret_manager_secret" "this" {
  for_each  = toset(local.secret_ids)
  secret_id = each.value
  labels    = local.common_labels

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_iam_member" "server_access" {
  for_each = local.server_secret_pairs

  secret_id = google_secret_manager_secret.this[each.value.secret_id].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = module.identity[each.value.node_name].member
}

resource "google_secret_manager_secret_iam_member" "version_adder" {
  for_each = local.secret_version_writers

  secret_id = google_secret_manager_secret.this[each.value.secret_id].secret_id
  role      = "roles/secretmanager.secretVersionAdder"
  member    = each.value.member
}
