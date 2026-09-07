output "management_subnet_id" {
  description = "ID of the subnet used by the bastion."
  value       = google_compute_subnetwork.management.id
}

output "workload_subnet_id" {
  description = "ID of the subnet used by workload VMs."
  value       = google_compute_subnetwork.workload.id
}

output "network_tags" {
  description = "Network tags used by firewall rules and Compute Engine instances."
  value       = local.network_tags
}
output "network_id" {
  description = "ID of the VPC."
  value       = google_compute_network.main.id
}

output "network_name" {
  description = "Name of the VPC."
  value       = google_compute_network.main.name
}

output "network_self_link" {
  description = "Self link of the VPC, for resources that address it by URL."
  value       = google_compute_network.main.self_link
}

output "region" {
  description = "Region both subnets live in. Derived from the provider, not from an input."
  value       = google_compute_subnetwork.workload.region
}

output "management_subnet_name" {
  description = "Name of the subnet used by the bastion."
  value       = google_compute_subnetwork.management.name
}

output "management_subnet_cidr" {
  description = "Range of the subnet used by the bastion."
  value       = google_compute_subnetwork.management.ip_cidr_range
}

output "management_subnet_gateway" {
  description = "Gateway address of the management subnet."
  value       = google_compute_subnetwork.management.gateway_address
}

output "workload_subnet_name" {
  description = "Name of the subnet used by workload VMs."
  value       = google_compute_subnetwork.workload.name
}

output "workload_subnet_cidr" {
  description = "Range of the subnet used by workload VMs."
  value       = google_compute_subnetwork.workload.ip_cidr_range
}

output "workload_subnet_gateway" {
  description = "Gateway address of the workload subnet."
  value       = google_compute_subnetwork.workload.gateway_address
}

output "router_name" {
  description = "Name of the Cloud Router carrying the NAT configuration."
  value       = google_compute_router.main.name
}

output "nat_name" {
  description = "Name of the Cloud NAT that gives the workload subnet outbound access."
  value       = google_compute_router_nat.main.name
}

output "firewall_rule_names" {
  description = "Name of every ingress rule this module creates, by purpose. The bootstrap rule is absent unless it is enabled."
  value = merge(
    {
      bastion_ssh  = google_compute_firewall.bastion_ssh.name
      workload_ssh = google_compute_firewall.workload_ssh.name
      ui_web       = google_compute_firewall.ui_web.name
      history_api  = google_compute_firewall.history_api.name
      postgresql   = google_compute_firewall.postgresql.name
    },
    {
      for rule in google_compute_firewall.bastion_ssh_bootstrap :
      "bastion_ssh_bootstrap" => rule.name
    },
  )
}
