variable "config" {
    type = any
}

variable "has_selected_vms" {
    type = bool
}

variable "vpc_cidr_block" {
    type = string
    default = "10.0.0.0/16"
}
