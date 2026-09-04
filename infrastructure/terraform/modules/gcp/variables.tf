variable "config" {
  description = "Complete project configuration decoded from JSON."
  type        = any
  nullable    = false
}

variable "enable_bastion_ssh_bootstrap" {
  type    = bool
  default = false
}

variable "secret_version_managers" {
  type    = list(string)
  default = []
}