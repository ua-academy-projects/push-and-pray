variable "config" {
  description = "Full parsed project configuration (see project_config_path in the root module)."
  type        = any
}

variable "network" {
  description = "Outputs of the azure_network module. Collections are empty when the configuration has no Azure VMs."
  type = object({
    resource_group_name            = string
    location                       = string
    vm_subnet_ids                  = map(string)
    security_group_ids             = map(string)
    application_security_group_ids = map(string)
  })
}
