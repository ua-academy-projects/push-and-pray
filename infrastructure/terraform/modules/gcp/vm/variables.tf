variable "config" {
  description = "Full parsed project configuration (see project_config_path in the root module)."
  type        = any
}

variable "network" {
  description = "Outputs of the gcp_network module. Subnet IDs are null when the configuration has no GCP VMs."
  type = object({
    management_subnet_id = string
    workload_subnet_id   = string
    network_tags         = map(string)
  })
}
