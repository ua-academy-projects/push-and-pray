variable "config" {
  description = "Project configuration decoded from the external JSON."
  type        = any
}
variable "network_id" {
  description = "Network receiving the firewall rules."
  type        = string
}
variable "enable_bastion_ssh_bootstrap" {
  type    = bool
  default = false
}

variable "database_mode" {
  description = "Database deployment mode."
  type        = string
  default     = "self_hosted"
}
