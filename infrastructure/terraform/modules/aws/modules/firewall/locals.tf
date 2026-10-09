locals {
  # Same four scopes GCP expresses as network tags. On AWS a scope is a
  # security group the instance belongs to, and rules reference the group
  # instead of matching a tag string.
  scopes = ["bastion", "k3s_server", "k3s_agent", "ingress"]

  node_scopes = ["k3s_server", "k3s_agent"]

  # A security group rule names one port range and one source, so every
  # combination the configuration asks for becomes a rule of its own.
  cluster_rules = {
    for rule in flatten([
      for entry in var.cluster.ports : [
        for combination in setproduct(entry.roles, entry.ports, var.cluster_cidrs) : {
          name     = entry.name
          protocol = entry.protocol
          scope    = combination[0]
          port     = combination[1]
          cidr     = combination[2]
        }
      ]
    ]) : "${rule.name}/${rule.scope}/${rule.port}/${rule.cidr}" => rule
  }

  icmp_rules = {
    for combination in setproduct(concat(local.node_scopes, ["bastion"]), var.cluster_cidrs) :
    "${combination[0]}/${combination[1]}" => {
      scope = combination[0]
      cidr  = combination[1]
    }
  }
}
