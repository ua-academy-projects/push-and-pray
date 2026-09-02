variable "resource_prefix" {
  description = "Prefix used for GCP VM resources."
  type        = string
}

variable "vm_name" {
  description = "Logical VM name."
  type        = string
}

variable "vm" {
  description = "Provider-independent configuration for this VM."
  type        = any
}

variable "vm_defaults" {
  description = "Default VM configuration."
  type        = any
}

variable "provider_mappings" {
  description = "Provider mappings for abstract VM configuration."
  type        = any
}

variable "common_labels" {
  description = "Common labels applied to GCP resources."
  type        = map(string)
}

variable "ssh_users" {
  description = "Public SSH keys keyed by Linux username."
  type        = map(string)
}

variable "management_subnet_id" {
  description = "ID of the management subnet."
  type        = string
}

variable "workload_subnet_id" {
  description = "ID of the workload subnet."
  type        = string
}

variable "network_tags_by_role" {
  description = "GCP network tags keyed by VM role."
  type        = map(string)
}

check "provider_mappings" {
  assert {
    condition = (
      can(var.provider_mappings.instance_types[local.vm.size].gcp.machine_type) &&
      can(var.provider_mappings.disk_types[local.vm.disk_type].gcp) &&
      can(var.provider_mappings.images[local.vm.image].gcp.image)
    )
    error_message = "The VM size, disk type, and image must have GCP provider mappings."
  }
}
