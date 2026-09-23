variable "config" {
  description = "Project configuration decoded from JSON."
  type        = any
  nullable    = false
}

variable "service_account_emails" {
  description = "VM service account emails keyed by VM name."
  type        = map(string)
  nullable    = false
}

variable "vms" {
  description = "Created GCP VMs keyed by configuration name."
  type        = any
  nullable    = false
}
