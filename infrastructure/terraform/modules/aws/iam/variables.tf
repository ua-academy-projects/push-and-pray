variable "config" {
    type = any
}

variable "selected_vms" {
    description = "VMs assigned to this cloud, cloud-filtered by the parent module."
    type        = any
}
