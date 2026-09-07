output "name" {
  description = "Name of the workload VM."
  value       = google_compute_instance.workload.name
}

output "internal_ip" {
  description = "Internal IP address of the workload VM."
  value       = google_compute_instance.workload.network_interface[0].network_ip
}

output "public_ip" {
  description = "Static external IP address, or null when none is assigned."
  value       = var.vm.assign_public_ip ? google_compute_address.public[0].address : null
}

output "network_tags" {
  description = "Effective network tags attached to the workload VM."
  value       = google_compute_instance.workload.tags
}

output "service_account_email" {
  description = "Email of the workload VM's dedicated service account."
  value       = google_service_account.workload.email
}

output "instance_id" {
  description = "Server-assigned unique identifier of the instance."
  value       = google_compute_instance.workload.instance_id
}

output "self_link" {
  description = "Self link of the instance, for resources that address it by URL."
  value       = google_compute_instance.workload.self_link
}

output "zone" {
  description = "Zone the instance runs in. Inherited from the provider, not from an input."
  value       = google_compute_instance.workload.zone
}

output "machine_type" {
  description = "Machine type the size label resolved to."
  value       = local.machine_type
}

output "boot_disk" {
  description = "What the boot disk labels resolved to, alongside its size."
  value = {
    image   = local.image
    type    = local.boot_disk_type
    size_gb = var.vm.boot_disk.size_gb
  }
}

output "role" {
  description = "Functional role of this VM, echoed back for callers indexing by role."
  value       = var.vm.role
}

output "identity" {
  description = "Email of the VM's dedicated service account. Named to match the AWS module, which returns a role ARN here."
  value       = google_service_account.workload.email
}

output "identity_member" {
  description = "The service account as an IAM member string, ready to use in a binding."
  value       = "serviceAccount:${google_service_account.workload.email}"
}

output "service_account_id" {
  description = "Fully qualified resource ID of the service account."
  value       = google_service_account.workload.id
}

output "service_account_unique_id" {
  description = "Numeric unique ID of the service account, which survives a rename."
  value       = google_service_account.workload.unique_id
}

output "public_address_name" {
  description = "Name of the reserved external address, or null when none is assigned."
  value       = one(google_compute_address.public[*].name)
}
