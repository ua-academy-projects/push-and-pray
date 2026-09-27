variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "zone" { type = string }
variable "resource_prefix" { type = string }
variable "tags" { type = map(string) }
variable "database" {
  type = object({
    name = string
    user = string
    port = number
  })
}
variable "managed_settings" {
  type = object({
    version  = string
    sku_name = string
  })
}
variable "administrator_password" {
  type      = string
  sensitive = true
}
variable "delegated_subnet_id" { type = string }
variable "private_dns_zone_id" { type = string }
