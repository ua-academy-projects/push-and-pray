variable "config" {
  type = any
}

variable "network_id" {
  type = string
}

variable "network_tags" {
  type = map(string)
}

variable "enable_bastion_ssh_bootstrap" {
  description = "Whether to temporarily allow direct bastion SSH on port 22 when the final SSH port differs."
  type        = bool
  default     = false
}
