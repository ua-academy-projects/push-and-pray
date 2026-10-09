variable "config" {
  description = "Full parsed project configuration (see project_config_path in the root module)."
  type        = any
}

variable "network" {
  description = "Outputs of the aws_network module. Subnet IDs are empty when the configuration selects no AWS EKS cluster."
  type        = any
}
