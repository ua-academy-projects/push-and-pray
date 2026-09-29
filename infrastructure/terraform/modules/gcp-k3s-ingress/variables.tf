variable "config" {
  description = "Validated project configuration."
  type        = any
}

variable "instance_self_links" {
  description = "Compute Engine instance self-links keyed by logical workload VM name."
  type        = map(string)
}
