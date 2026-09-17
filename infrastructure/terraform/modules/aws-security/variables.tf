variable "config" {
  description = "Project configuration decoded from the external JSON."
  type        = any
}
variable "vpc_id" {
  description = "VPC receiving the security groups."
  type        = string
}
variable "enable_bastion_ssh_bootstrap" {
  description = "Temporarily allow port 22 for initial Ansible access."
  type        = bool
  default     = false
}

variable "database_mode" {
  description = "Database deployment mode."
  type        = string
  default     = "self_hosted"
}
