variable "config" {
    type = any
}

variable "vpc_id" {
    type = string
}

variable "enable_bastion_ssh_bootstrap" {
    type = bool
    default = false
}
