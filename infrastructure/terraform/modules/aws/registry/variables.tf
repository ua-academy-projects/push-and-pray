variable "config" {
  description = "Full parsed project configuration (see project_config_path in the root module)."
  type        = any
}

variable "vm" {
  description = "The aws_vm module. Only the shared node role is read, to grant it pull-only access."
  type        = any
}
