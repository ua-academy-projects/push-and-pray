variable "config" {
  description = "Full parsed project configuration (see project_config_path in the root module)."
  type        = any
}

variable "vm" {
  description = "The aws_vm module. Only the shared k3s node role is read, to grant it pull-only access."
  type        = any
}

variable "eks" {
  description = "The aws_eks module. Only the registry credential refresh role is read, to grant it the same pull-only access the k3s node role gets."
  type        = any
}
