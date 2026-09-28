variable "config" {
  description = "Validated project configuration."
  type        = any
}

variable "instance_self_links" {
  description = "Compute Engine instance self-links keyed by logical workload VM name."
  type        = map(string)
}

variable "networks" {
  description = "GCP network identifiers keyed by logical location."
  type = map(object({
    network_id        = string
    public_subnet_id  = string
    private_subnet_id = string
  }))
}
