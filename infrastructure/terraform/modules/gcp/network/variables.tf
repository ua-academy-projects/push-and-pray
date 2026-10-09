variable "config" {
  type = any
}

variable "has_selected_vms" {
  type = bool
}

variable "managed_kubernetes_enabled" {
  type    = bool
  default = false
}
