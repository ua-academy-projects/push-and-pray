variable "config" {
  description = "Project configuration. The hostname, the VM to publish and the Cloudflare settings are all derived from it."
  type = object({
    default_cloud = string
    vms = map(object({
      role            = string
      cloud           = optional(string)
      public_endpoint = optional(object({ hostname = string }))
    }))
    cloudflare = optional(object({
      enabled   = optional(bool, false)
      zone_name = optional(string, "")
      ttl       = optional(number, 60)
      comment   = optional(string, "")
      proxied   = optional(bool, false)
    }), {})
  })
}

variable "aws_vms" {
  description = "Created AWS instances keyed by VM configuration name; only the public address is read."
  type        = map(object({ public_ip = optional(string) }))
  default     = {}
}

variable "gcp_vms" {
  description = "Created GCE instances keyed by VM configuration name; only the public address is read."
  type        = map(object({ public_ip = optional(string) }))
  default     = {}
}
