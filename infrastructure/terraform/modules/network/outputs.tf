output "network_name" {
  description = "Name of the VPC network."
  value       = google_compute_network.vpc.name
}

output "network_id" {
  description = "Fully qualified ID of the VPC network, for use by other modules."
  value       = google_compute_network.vpc.id
}

output "network_self_link" {
  description = "Self link of the VPC network."
  value       = google_compute_network.vpc.self_link
}

output "public_subnet" {
  description = "Public (bastion) subnet: name, id and CIDR."
  value = {
    name = google_compute_subnetwork.public.name
    id   = google_compute_subnetwork.public.id
    cidr = google_compute_subnetwork.public.ip_cidr_range
  }
}

output "private_subnet" {
  description = "Private (workload) subnet: name, id, CIDR and secondary ranges."
  value = {
    name             = google_compute_subnetwork.private.name
    id               = google_compute_subnetwork.private.id
    cidr             = google_compute_subnetwork.private.ip_cidr_range
    secondary_ranges = var.private_secondary_ranges
    google_access    = google_compute_subnetwork.private.private_ip_google_access
  }
}

output "network_tags" {
  description = "Network tags an instance must carry to be matched by the firewall rules."
  value = {
    bastion = local.tag_bastion
    app     = local.tag_app
    db      = local.tag_db
  }
}

output "nat_name" {
  description = "Name of the Cloud NAT gateway, or null when NAT is disabled."
  value       = var.enable_nat ? google_compute_router_nat.nat[0].name : null
}

output "nat_egress_ips" {
  description = "Static egress IPs used by Cloud NAT. Empty when NAT allocates addresses automatically - share these for partner IP allow-listing."
  value       = google_compute_address.nat[*].address
}

output "firewall_rules" {
  description = "Names of every firewall rule created, in priority order. Handy for `gcloud compute firewall-rules describe`."
  value = compact([
    google_compute_firewall.bastion_ssh_ingress.name,
    google_compute_firewall.ssh_from_bastion.name,
    google_compute_firewall.app_internal.name,
    google_compute_firewall.db_from_app.name,
    google_compute_firewall.internal_icmp.name,
    google_compute_firewall.deny_all_ingress.name,
  ])
}