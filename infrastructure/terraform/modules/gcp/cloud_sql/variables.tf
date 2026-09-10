variable "config" {
    type = any
}

variable "has_selected_vms" {
    type = bool
}

variable "network_self_link" {
    type = string
    default = null
}

variable "db_password_secret_id" {
    type = string
    default = null
}