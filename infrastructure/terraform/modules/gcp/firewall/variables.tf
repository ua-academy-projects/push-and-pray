variable "config" {
  type = any
}

variable "network_id" {
  type = string
}

variable "network_tags" {
  type = map(string)
}

variable "has_selected_vms" {
  type = bool
}