variable "config" {
  description = "Structured project configuration decoded once by the root module."
  type        = any
  validation {
    condition = alltrue([
      for vm in values(var.config.vms) : (
        can(var.config.cloud_mappings.regions[try(vm.region, var.config.default_region)].gcp.region) &&
        can(var.config.cloud_mappings.regions[try(vm.region, var.config.default_region)].gcp.zone) &&
        can(var.config.cloud_mappings.sizes[vm.size].gcp) &&
        can(var.config.cloud_mappings.disk_types[vm.boot_disk.type].gcp) &&
        can(var.config.cloud_mappings.images[vm.image].gcp)
      ) if try(vm.cloud, var.config.default_cloud) == "gcp"
    ])
    error_message = "Every GCP VM must have region, size, disk and image mappings for its provider."
  }

}

variable "resource_prefix" {
  description = "Shared deployment resource name prefix."
  type        = string
}

variable "common_labels" {
  description = "Validated cross-cutting deployment labels."
  type        = map(string)
}

variable "network" {
  description = "Existing provider network outputs; null when this provider has no VMs."
  type = object({
    management_subnet_id = string
    workload_subnet_id   = string
  })
}

variable "ssh_users" {
  description = "Public SSH keys keyed by Linux username."
  type        = map(string)
}

variable "startup_scripts" {
  description = "Optional non-secret bootstrap shell scripts keyed by VM configuration key."
  type        = map(string)
  default     = {}
}
