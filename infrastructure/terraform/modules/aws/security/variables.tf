variable "vpc_id" {
  type = string
}

variable "resource_prefix" {
  type = string
}

variable "bastion_ssh_port" {
  type = number

}
variable "bastion_allowed_cidrs" {
  type = list(string)
}

variable "ui_public_ports" {
  type = list(string)
}

variable "history_api_port" {
  type = number
}

variable "postgresql_port" {
  type = number
}
variable "rabbitmq_port" {
  type = number
}
variable "redis_port" {
  type = number
}
variable "enable_bastion_ssh_bootstrap" {
  type = bool
}

variable "managed_database_enabled" {
  description = "Whether to create the security group used only by a private RDS instance."
  type        = bool
  default     = false
}

variable "tags" {
  type = map(string)
}
