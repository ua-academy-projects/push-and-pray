variable "resource_prefix" { type = string }

variable "vpc_cidr" { type = string }

variable "management_subnet_cidr" { type = string }

variable "workload_subnet_cidr" { type = string }

variable "public_subnet_cidr" { type = string }

variable "availability_zone" { type = string }

variable "tags" { type = map(string) }
