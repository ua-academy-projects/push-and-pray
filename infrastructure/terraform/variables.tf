variable "project_config_path" {
  description = "Path to the external JSON file containing project-specific configuration."
  type        = string
  nullable    = false

  validation {
    condition     = fileexists(var.project_config_path)
    error_message = "project_config_path must point to an existing file."
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
