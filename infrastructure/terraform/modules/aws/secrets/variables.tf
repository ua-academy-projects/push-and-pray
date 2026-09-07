variable "config" {
  description = "Full parsed project configuration (see project_config_path in the root module)."
  type        = any
}

variable "vms" {
  description = "Outputs of the aws_vm module, keyed by name."
  type = map(object({
    role_name = string
  }))
}
