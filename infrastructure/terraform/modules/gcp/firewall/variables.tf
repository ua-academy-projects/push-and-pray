variable "config" {
  type = any
}

variable "selected_vms" {
  description = "VMs assigned to this cloud, cloud-filtered by the parent module."
  type        = any
}

variable "network_id" {
  type = string
}

variable "network_tags" {
  type = map(string)
}

variable "has_selected_vms" {
  type = bool
}