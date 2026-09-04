variable "name" {
  type = string
}

variable "role" {
  type = string
}

variable "ami_id" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "security_group_id" {
  type = string
}

variable "private_ip" {
  type = string
}

variable "boot_disk_size_gb" {
  type = number
}

variable "boot_disk_type" {
  type = string
}

variable "assign_public_ip" {
  type = bool
}

variable "ssh_users" {
  type = map(string)
}

variable "tags" {
  type = map(string)
}

variable "iam_instance_profile" {
  type = string
}