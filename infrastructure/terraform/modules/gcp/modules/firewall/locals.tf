locals {
  # One scope per node role, one for the bastion, and one for the nodes that
  # hold a public address and answer for the ingress. A network tag takes
  # neither an underscore nor an upper-case letter, so the role name is
  # rewritten for the tag and kept as is for the key.
  scopes = ["bastion", "k3s_server", "k3s_agent", "ingress"]

  network_tags = {
    for scope in local.scopes : scope => "${var.resource_prefix}-${replace(scope, "_", "-")}"
  }

  node_tags = [local.network_tags.k3s_server, local.network_tags.k3s_agent]

  cluster_ports = { for entry in var.cluster.ports : entry.name => entry }
}
