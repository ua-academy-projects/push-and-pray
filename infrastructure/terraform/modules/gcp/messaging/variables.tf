variable "project_id" { type = string }
variable "resource_prefix" { type = string }
variable "labels" { type = map(string) }
variable "settings" {
  type = object({
    queue_name                 = string
    visibility_timeout_seconds = number
    max_delivery_attempts      = number
  })
}
variable "publisher_service_account_email" { type = string }
variable "consumer_service_account_email" { type = string }
