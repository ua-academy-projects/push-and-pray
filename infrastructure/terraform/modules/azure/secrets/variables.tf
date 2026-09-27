variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "resource_prefix" { type = string }
variable "subscription_id" { type = string }
variable "tenant_id" { type = string }
variable "deployer_object_id" { type = string }
variable "tags" { type = map(string) }
variable "secret_ids" { type = set(string) }
variable "secret_ids_by_vm" { type = map(list(string)) }
variable "principal_ids" { type = map(string) }
variable "secret_values" {
  type      = map(string)
  sensitive = true
  default   = {}
}
