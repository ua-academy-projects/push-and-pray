locals {
  # Same four scopes GCP expresses as network tags and AWS as security groups.
  # On Azure a scope is an application security group a network interface
  # joins, and every rule lives in one security group on the subnets.
  scopes = ["bastion", "k3s_server", "k3s_agent", "ingress"]

  node_scopes = ["k3s_server", "k3s_agent"]

  # Rules are evaluated by priority, lowest first. The fixed allow rules sit in
  # one band, the rules cluster.ports asks for in the next, ten apart in the
  # order they are written, and the deny that makes the network default-closed
  # comes last, below all of them.
  priorities = {
    bastion_ssh           = 100
    bastion_ssh_bootstrap = 110
    bastion_tailscale     = 120
    bastion_forwarding    = 130
    node_ssh_bastion      = 140
    node_ssh_tailnet      = 150
    cluster_icmp          = 160
    ingress_web           = 170
    deny_vnet_inbound     = 4000
  }

  cluster_ports = {
    for index, entry in var.cluster.ports : entry.name => merge(entry, {
      priority = 200 + index * 10
    })
  }
}
