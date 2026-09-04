variable "config" {
  description = "Shared project configuration."
  type        = any
}

variable "key_names_by_location" {
  description = "EC2 key-pair names keyed by abstract location."
  type        = map(string)
}

variable "management_subnet_ids" {
  description = "Management subnet IDs keyed by abstract location."
  type        = map(string)
}

variable "workload_subnet_ids" {
  description = "Workload subnet IDs keyed by abstract location."
  type        = map(string)
}

variable "security_group_ids_by_location" {
  description = "AWS security-group IDs keyed by abstract location and VM role."
  type        = map(map(string))
}