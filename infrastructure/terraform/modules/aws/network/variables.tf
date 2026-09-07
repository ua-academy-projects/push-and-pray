variable "config" {
    type = any
}

variable "vpc_cidr_block" {
    type = string
    default = "10.0.0.0/16"
}
