variable "config" {
  type = any
}

variable "selected_vms" {
  description = "VMs assigned to this cloud, cloud-filtered by the parent module."
  type        = any
}

variable "has_selected_vms" {
  type = bool
}

variable "instance_ids" {
  type = map(string)
}