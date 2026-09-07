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
variable "enable_bastion_ssh_bootstrap" {
  type = bool
}

variable "tags" {
  type = map(string)
}
