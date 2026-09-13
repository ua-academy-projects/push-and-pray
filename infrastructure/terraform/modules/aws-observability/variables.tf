variable "config" {
  description = "Validated project configuration."
  type        = any
}

variable "role_names" {
  description = "IAM role names keyed by logical AWS VM name."
  type        = map(string)
}

variable "instance_ids" {
  description = "EC2 instance IDs keyed by logical VM name."
  type        = map(string)
}

variable "volume_ids" {
  description = "EBS volume IDs keyed by logical VM and disk name."
  type        = map(map(string))
}
