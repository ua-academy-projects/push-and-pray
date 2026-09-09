output "vms" {
  description = "VM resource attributes keyed by project VM key."
  value = {
    for name, instance in google_compute_instance.workload : name => {
      name                  = instance.name
      instance_id           = instance.instance_id
      internal_ip           = instance.network_interface[0].network_ip
      public_ip             = try(google_compute_address.public[name].address, null)
      network_tags          = instance.tags
      service_account_email = google_service_account.workload[name].email
    }
  }
}

output "resolved_vms" {
  description = "Provider-resolved VM configuration, independent of created resources."
  value       = local.resolved_vms
}
