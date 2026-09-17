variable "config" {
  description = "Validated project configuration."
  type        = any
}

variable "networks" {
  description = "AWS network identifiers keyed by logical location."
  type        = any
}

variable "security_group_ids" {
  description = "AWS security group IDs keyed by logical location and functional tag."
  type        = map(map(string))
}

variable "instance_profiles" {
  description = "IAM instance profile names keyed by logical workload VM name."
  type        = map(string)
}

variable "bootstrap_key_names" {
  description = "AWS key pair names keyed by logical location."
  type        = map(string)
}
