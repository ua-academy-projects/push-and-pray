variable "config" {
  description = "Validated project configuration."
  type        = any
}

variable "networks" {
  description = "AWS network identifiers keyed by logical location."
  type = map(object({
    region               = string
    management_subnet_id = string
    workload_subnet_id   = string
  }))
}

variable "security_group_ids" {
  description = "AWS security group IDs keyed by logical location and VM tag."
  type        = map(map(string))
}

variable "instance_profiles" {
  description = "IAM instance profile names keyed by logical AWS VM name."
  type        = map(string)
}
