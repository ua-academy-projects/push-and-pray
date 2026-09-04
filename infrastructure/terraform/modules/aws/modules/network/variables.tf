variable "resource_prefix" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "management_subnet_cidr" {
  type = string
}

variable "workload_subnet_cidr" {
  type = string
}

variable "availability_zone" {
  type = string
}

variable "tags" {
  type = map(string)
}
variable "bastion_ssh_port" {
  type = number
}

variable "bastion_allowed_cidrs" {
  type = list(string)
}

variable "ui_public_ports" {
  type = list(number)
}

variable "history_api_port" {
  type = number
}

variable "postgresql_port" {
  type = number
}