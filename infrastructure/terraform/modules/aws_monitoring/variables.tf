variable "config" {
  description = "Project configuration decoded from JSON."
  type        = any
  nullable    = false
}

variable "role_names" {
  description = "EC2 IAM role names keyed by VM name."
  type        = map(string)
  nullable    = false
}

variable "vms" {
  description = "Created AWS VMs keyed by configuration name."
  type        = any
  nullable    = false
}
