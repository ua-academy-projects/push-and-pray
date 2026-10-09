variable "config" {
  type = any
}

variable "enabled" {
  type = bool
}

variable "subnet_ids" {
  type    = list(string)
  default = []
}

variable "bastion_security_group_id" {
  type    = string
  default = null
}
