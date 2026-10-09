variable "config" {
  description = "Project configuration. Both published hostnames and the entry node they resolve to are derived from it."
  type = object({
    managed_kubernetes = optional(bool, false)
    ingress = object({
      hostname = string
    })
    kubernetes = object({
      api_endpoint = optional(string)
      entry_node   = optional(string)
    })
    cloudflare = optional(object({
      enabled   = optional(bool, false)
      zone_name = optional(string, "")
      ttl       = optional(number, 60)
      comment   = optional(string, "")
      proxied   = optional(bool, false)
    }), {})
    headlamp = optional(object({
      enabled  = optional(bool, false)
      hostname = optional(string, "")
    }), {})
  })
}

variable "vm" {
  description = "The aws_vm module. Only the entry node's public address is read, and only in self-hosted Kubernetes mode. In managed Kubernetes mode this module publishes no records at all, so it needs no address and no reference to the EKS module: the load balancer those records point at is created by the deployment, not by Terraform."
  type        = any
}
