variable "resource_prefix" {
  description = "Prefix shared by every resource name."
  type        = string
}

variable "identities" {
  description = "IAM role name of every instance identity that ships logs, keyed by instance name."
  type        = map(string)
}

variable "retention_days" {
  description = "How long the log group keeps an entry."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
