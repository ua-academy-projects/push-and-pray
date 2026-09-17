variable "zone_id" {
  description = "Existing Cloudflare zone identifier. It is not a credential."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.zone_id))
    error_message = "zone_id must be a 32-character Cloudflare identifier."
  }
}

variable "hostname" {
  type = string
}

variable "ipv4_address" {
  type = string
}

variable "proxied" {
  type    = bool
  default = false
}

variable "ttl" {
  type    = number
  default = 60

  validation {
    condition     = var.ttl == 1 || (var.ttl >= 60 && var.ttl <= 86400)
    error_message = "ttl must be 1 (automatic) or between 60 and 86400 seconds."
  }
}
