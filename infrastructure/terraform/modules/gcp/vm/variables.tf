variable "config" {
  description = "Shared project configuration."
  type        = any
}

variable "project_services" {
  description = "GCP project services enabled before VM creation."
  type        = list(string)
}

variable "management_subnet_ids" {
  description = "Management subnet IDs keyed by abstract location."
  type        = map(string)
}

variable "workload_subnet_ids" {
  description = "Workload subnet IDs keyed by abstract location."
  type        = map(string)
}

variable "network_tags_by_location" {
  description = "GCP network tags keyed by abstract location and VM role."
  type        = map(map(string))
}

check "provider_mappings" {
  assert {
    condition = alltrue([
      for vm in values(local.vms) : (
        can(var.config.provider_mappings.instance_types[vm.size].gcp.machine_type) &&
        can(var.config.provider_mappings.disk_types[vm.disk_type].gcp) &&
        can(var.config.provider_mappings.images[vm.image].gcp.image) &&
        can(var.config.locations[vm.location].gcp.region) &&
        can(var.config.locations[vm.location].gcp.zone)
      )
    ])
    error_message = "Every selected VM size, disk type, image, and location must have GCP provider mappings."
  }
}
