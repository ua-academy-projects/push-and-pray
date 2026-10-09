variable "project_config_path" {
  description = "Existing non-secret OilScope project configuration."
  type        = string

  validation {
    condition     = fileexists(var.project_config_path)
    error_message = "project_config_path must point to the existing project configuration."
  }
}

variable "vnet_cidr" {
  description = "CIDR for the isolated managed-cluster VNet."
  type        = string
  default     = "10.240.0.0/16"
}

variable "node_subnet_cidr" {
  description = "CIDR for AKS worker nodes in the isolated VNet."
  type        = string
  default     = "10.240.1.0/24"
}
