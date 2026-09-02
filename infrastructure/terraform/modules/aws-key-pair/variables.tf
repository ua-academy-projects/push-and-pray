variable "resource_prefix" {
  description = "Prefix used for the AWS key-pair name."
  type        = string
}

variable "ssh_users" {
  description = "Public SSH keys keyed by Linux username."
  type        = map(string)
}

variable "tags" {
  description = "Common tags applied to the AWS key pair."
  type        = map(string)
}
