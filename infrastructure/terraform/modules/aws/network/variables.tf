variable "name_prefix" {
    type = string
}

variable "environment" {
    type = string
}

variable "management_subnet_cidr" {
    type = string
}

variable "workload_subnet_cidr" {
    type = string
}

variable "vpc_cidr_block" {
    type = string
    default = "10.0.0.0/16"
}

variable "region" {
    type = string
}

variable "regions" {
    type = any
}

variable "bastion_ssh_port" {
    type = number

}

variable "bastion_allowed_cidrs" {
    type = list(string)
}

variable "enable_bastion_ssh_bootstrap" {
    type = bool
    default = false
}

variable "history_api_port" {
    type = number
}

variable "postgresql_port" {
    type = number
}

variable "ui_public_ports" {
    type = list(string)
}
