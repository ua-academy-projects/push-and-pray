output "vms" {
  description = "GCP workload VMs, keyed by name."
  value = {
    for name, instance in google_compute_instance.workload : name => {
      name                  = instance.name
      internal_ip           = instance.network_interface[0].network_ip
      public_ip             = local.gcp_vms[name].assign_public_ip ? google_compute_address.public[name].address : null
      network_tags          = instance.tags
      service_account_email = google_service_account.workload[name].email
    }
  }
}

output "gcp_vms" {
  description = "Resolved GCP VM configuration (post cloud/size/image resolution), keyed by name."
  value       = local.gcp_vms
}
