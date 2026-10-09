variable "config" {
  description = "Validated project configuration."
  type        = any
}

variable "network" {
  description = "GCP network identifiers for the managed cluster location."
  type = object({
    network_id        = string
    public_subnet_id  = string
    private_subnet_id = string
  })
}
