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

output "public_address_name" {
  description = "Name of the reserved external address, or null when none is assigned."
  value       = one(google_compute_address.public[*].name)
}
