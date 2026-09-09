variable "config" {
    type = any
}

variable "has_selected_vms" {
    type = bool
}

variable "vpc_id" {
    type = string
}

variable "management_subnet_id" {
    type = string
}

variable "workload_subnet_id" {
    type = string
}
