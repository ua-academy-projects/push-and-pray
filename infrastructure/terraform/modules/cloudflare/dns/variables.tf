variable "config" {
  description = "Project configuration. Both published hostnames and the entry node they resolve to are derived from it."
  type = object({
    ingress = object({
      hostname = string
    })
    kubernetes = object({
      api_endpoint = string
      entry_node   = string
    })
    cloudflare = optional(object({
      enabled   = optional(bool, false)
      zone_name = optional(string, "")
      ttl       = optional(number, 60)
      comment   = optional(string, "")
      proxied   = optional(bool, false)
    }), {})
  })
}

variable "vm" {
  description = "The aws_vm module. Only the entry node's public address is read."
  type        = any
}
