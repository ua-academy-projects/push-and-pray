output "network_tags" {
  description = "Network tag by scope. An instance carries the tag of its role, and a node with a public address also carries the ingress tag."
  value       = local.network_tags
}

output "firewall_rule_names" {
  description = "Name of every ingress rule this module creates, by purpose. The bootstrap rule is absent unless it is enabled; cluster rules are keyed cluster/<name>."
  value = merge(
    {
      bastion_ssh        = google_compute_firewall.bastion_ssh.name
      bastion_tailscale  = google_compute_firewall.bastion_tailscale.name
      bastion_forwarding = google_compute_firewall.bastion_forwarding.name
      node_ssh           = google_compute_firewall.node_ssh.name
      cluster_icmp       = google_compute_firewall.cluster_icmp.name
      ingress_web        = google_compute_firewall.ingress_web.name
    },
    {
      for rule in google_compute_firewall.bastion_ssh_bootstrap :
      "bastion_ssh_bootstrap" => rule.name
    },
    { for name, rule in google_compute_firewall.cluster : "cluster/${name}" => rule.name },
  )
}

output "scopes" {
  description = "The scopes this contract is written in terms of."
  value       = sort(local.scopes)
}
