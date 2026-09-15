output "network_tags" {
  description = "Network tags used by these rules and by Compute Engine instances. An instance carries the tag matching its role."
  value       = local.network_tags
}

output "firewall_rule_names" {
  description = "Name of every ingress rule this module creates, by purpose. The bootstrap rule is absent unless it is enabled; postgresql exists only with a self-hosted database, amqp and redis only with a managed one."
  value = merge(
    {
      bastion_ssh  = google_compute_firewall.bastion_ssh.name
      workload_ssh = google_compute_firewall.workload_ssh.name
      ui_web       = google_compute_firewall.ui_web.name
      history_api  = google_compute_firewall.history_api.name
    },
    {
      for rule in google_compute_firewall.bastion_ssh_bootstrap :
      "bastion_ssh_bootstrap" => rule.name
    },
    { for rule in google_compute_firewall.postgresql : "postgresql" => rule.name },
    { for rule in google_compute_firewall.amqp : "amqp" => rule.name },
    { for rule in google_compute_firewall.redis : "redis" => rule.name },
  )
}

output "scopes" {
  description = "The role scopes this contract is written in terms of."
  value       = sort(keys(local.network_tags))
}
