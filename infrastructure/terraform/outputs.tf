# network

output "network_name" {
  description = "Name of the VPC network."
  value       = module.network.network_name
}

output "network_self_link" {
  description = "Self link of the VPC network."
  value       = module.network.network_self_link
}

output "management_subnet" {
  description = "Management (bastion) subnet: name, id and CIDR."
  value       = module.network.management_subnet
}

output "workload_subnet" {
  description = "Application workload subnet: name, id, CIDR and secondary ranges."
  value       = module.network.workload_subnet
}

output "network_tags" {
  description = "Network tags an instance must carry to be matched by the firewall rules."
  value       = module.network.network_tags
}

output "ui_public_ports" {
  description = "Ports published to the internet for instances carrying the ui network tag."
  value       = module.network.ui_public_ports
}

output "firewall_rules" {
  description = "Ingress firewall rules created for this VPC."
  value       = module.network.firewall_rules
}

output "egress_firewall_rules" {
  description = "Egress firewall rules. Empty unless restrict_egress is enabled."
  value       = module.network.egress_firewall_rules
}

output "nat_name" {
  description = "Name of the Cloud NAT gateway that gives private instances outbound access."
  value       = module.network.nat_name
}

output "nat_egress_ips" {
  description = "Static egress IPs used by Cloud NAT. Empty when NAT allocates addresses automatically."
  value       = module.network.nat_egress_ips
}

# bastion

output "bastion_name" {
  description = "Name of the bastion instance."
  value       = module.bastion.bastion_name
}

output "bastion_public_ip" {
  description = "Static external IP of the bastion: the single entry point into the VPC."
  value       = module.bastion.bastion_public_ip
}

output "bastion_private_ip" {
  description = "Internal IP of the bastion inside the VPC."
  value       = module.bastion.bastion_private_ip
}

output "bastion_service_account" {
  description = "Email of the dedicated bastion service account."
  value       = module.bastion.bastion_service_account
}

output "ssh_port" {
  description = "Team-approved non-default SSH port. Port 22 is closed everywhere."
  value       = local.config.bastion.ssh_port
}

output "ssh_users" {
  description = "Usernames with a public key installed on the bastion."
  value       = module.bastion.ssh_users
}

output "bastion_ssh_command" {
  description = "Ready-to-run SSH command for the bastion. Replace <user> with your own username."
  value       = module.bastion.bastion_ssh_command
}

output "bastion_proxy_jump_command" {
  description = "Template for reaching a private instance through the bastion with ProxyJump."
  value       = module.bastion.bastion_proxy_jump_command
}

# workload compute

output "workload_vm_names" {
  description = "Compute Engine instance names keyed by workload role."
  value = {
    for role, vm in module.workload_vm : role => vm.name
  }
}

output "workload_internal_ips" {
  description = "Reserved internal IPv4 addresses keyed by workload role."
  value = {
    for role, vm in module.workload_vm : role => vm.internal_ip
  }
}

output "workload_external_ips" {
  description = "External IPv4 addresses keyed by workload role; null for private VMs."
  value = {
    for role, vm in module.workload_vm : role => vm.external_ip
  }
}

output "workload_service_accounts" {
  description = "Dedicated service-account emails keyed by workload role."
  value = {
    for role, account in google_service_account.workload : role => account.email
  }
}

# secrets

output "secret_ids" {
  description = "Secret Manager secret IDs created from the project configuration. Secret values are never exposed by this configuration."
  value       = sort([for secret in google_secret_manager_secret.this : secret.secret_id])
}

output "secret_resource_names" {
  description = "Fully qualified Secret Manager resource names (projects/*/secrets/*) keyed by secret ID."
  value = {
    for id, secret in google_secret_manager_secret.this : id => secret.name
  }
}

output "secret_access_map" {
  description = "Which workload service accounts may read which secret. Use this to review least privilege without opening the console."
  value = {
    for secret_id in local.secret_ids : secret_id => sort([
      for pair in local.vm_secret_pairs :
      google_service_account.workload[pair.vm_name].email
      if pair.secret_id == secret_id
    ])
  }
}
