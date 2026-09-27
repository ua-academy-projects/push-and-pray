variable "config" {
  description = "Decoded project configuration shared by all cloud modules."
  type        = any
}

variable "enable_bastion_ssh_bootstrap" {
  description = "Temporarily allow port 22 while a bastion transitions to its configured SSH port."
  type        = bool
  default     = false
}
