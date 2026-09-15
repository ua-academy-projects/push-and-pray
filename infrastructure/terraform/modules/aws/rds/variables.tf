variable "config" {
    type = any
}

variable "has_selected_vms" {
    type = bool
}

variable "vpc_id" {
    type = string
    default = null
}

variable "database_subnet_ids"{
    type = list(string)
    default = []
}

variable "db_password_secret_id" {
    type = string
    default = null
}