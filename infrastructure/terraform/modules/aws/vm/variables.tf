variable "name" { type = string }
variable "role" { type = string }
variable "subnet_id" { type = string }
variable "security_group_ids" { type = list(string) }
variable "internal_ip" { type = string }
variable "instance_type" { type = string }
variable "ami_id" {
  type = string
  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "ami_id must be an explicit AMI ID valid in the selected AWS region."
  }
}
variable "root_volume_size_gb" { type = number }
variable "root_volume_type" { type = string }
variable "assign_public_ip" { type = bool }
variable "ssh_users" { type = map(string) }
variable "enable_nat" { type = bool }
variable "free_tier_guardrails" { type = bool }
variable "tags" { type = map(string) }
