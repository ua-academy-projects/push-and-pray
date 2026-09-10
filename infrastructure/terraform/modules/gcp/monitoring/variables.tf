variable "config" {
  type = any
}

variable "has_selected_vms" {
  type = bool
}

variable "instance_ids" {
  type = map(string)
}