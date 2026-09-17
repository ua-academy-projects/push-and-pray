variable "config" {
  description = "Project configuration decoded from the external JSON."
  type        = any
}

variable "aws_secret_arns" {
  description = "Secrets Manager ARNs readable by the shared EC2 runtime role."
  type        = list(string)
  default     = []
}

variable "enable_aws_secret_access" {
  description = "Create the EC2 Secrets Manager read policy."
  type        = bool
  default     = false
}
