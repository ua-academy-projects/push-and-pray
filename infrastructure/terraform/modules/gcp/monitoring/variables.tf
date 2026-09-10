variable "config" {
  description = "Shared project configuration."
  type        = any
}

variable "vms" {
  description = "Created GCP VMs keyed by logical VM name."
  type        = any
}
