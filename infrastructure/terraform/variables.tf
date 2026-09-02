variable "project_config_path" {
  description = "Path to the external JSON file containing project-specific configuration."
  type        = string
  nullable    = false

  validation {
    condition     = fileexists(var.project_config_path)
    error_message = "project_config_path must point to an existing file."
  }
}

variable "enable_bastion_ssh_bootstrap" {
  description = "Temporarily allow direct bastion SSH on port 22 while Ansible configures the final SSH port. Disable after bootstrap."
  type        = bool
  default     = false
}

check "vm_size_references" {
  assert {
    condition = alltrue([
      for vm in values(local.config.vms) : contains(keys(local.config.sizes), vm.size)
    ])
    error_message = "Every VM size must refer to a key in config.sizes."
  }
}

check "vm_instance_type_references" {
  assert {
    condition = alltrue([
      for vm in values(local.configured_vms) : can(local.config.provider_mappings.instance_types[vm.size][vm.cloud])
    ])
    error_message = "Every VM size must have an instance type mapping for its selected cloud."
  }
}

check "vm_disk_type_references" {
  assert {
    condition = alltrue([
      for vm in values(local.configured_vms) : can(local.config.provider_mappings.disk_types[vm.disk_type][vm.cloud])
    ])
    error_message = "Every VM disk_type must have a provider mapping for its selected cloud."
  }
}

check "vm_image_references" {
  assert {
    condition = alltrue([
      for vm in values(local.configured_vms) : can(local.config.provider_mappings.images[vm.image][vm.cloud])
    ])
    error_message = "Every VM image must have a provider mapping for its selected cloud."
  }
}

check "vm_location_references" {
  assert {
    condition = alltrue([
      for vm in values(local.config.vms) : contains(keys(local.config.locations), vm.location)
    ])
    error_message = "Every VM location must refer to a key in config.locations."
  }
}
