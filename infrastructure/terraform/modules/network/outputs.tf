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
    ui      = local.tag_ui
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
  value = compact(concat([
    google_compute_firewall.bastion_ssh_ingress.name,
    google_compute_firewall.ssh_from_bastion.name,
    google_compute_firewall.app_internal.name,
    google_compute_firewall.db_from_app.name,
    google_compute_firewall.internal_icmp.name,
    google_compute_firewall.deny_all_ingress.name,
    ],
    google_compute_firewall.ui_public_ingress[*].name,
  ))
}
output "egress_firewall_rules" {
  description = "Names of the egress rules. Empty when restrict_egress is false and the permissive implied egress rule applies."
  value = compact(concat(
    google_compute_firewall.egress_internal[*].name,
    google_compute_firewall.egress_metadata_server[*].name,
    google_compute_firewall.egress_dns_ntp[*].name,
    google_compute_firewall.egress_internet[*].name,
    google_compute_firewall.deny_all_egress[*].name,
  ))
}

output "default_route_name" {
  description = "Name of the explicitly managed default route, or null when the auto-created route is kept."
  value       = var.manage_default_route ? google_compute_route.default_internet[0].name : null
}

output "ssh_port" {
  description = "Non-default SSH port opened by the firewall rules. The bastion module must configure sshd on the same port."
  value       = var.ssh_port
}

output "bastion_allowed_cidrs" {
  description = "Source ranges currently allowed to reach the bastion on ssh_port."
  value       = var.bastion_allowed_cidrs
}

output "ui_public_ports" {
  description = "Ports published to the internet for instances carrying the ui tag. Empty when the public UI rule is disabled."
  value       = var.enable_ui_public_ingress ? var.ui_public_ports : []
}

output "app_ports" {
  description = "Application ports reachable from inside the VPC only."
  value       = var.app_ports
}

output "db_port" {
  description = "Database port, reachable only from instances tagged as application servers."
  value       = var.db_port
}
