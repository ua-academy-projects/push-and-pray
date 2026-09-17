variable "project_config_path" {
  description = "Path to the external JSON file containing project-specific configuration."
  type        = string
  nullable    = false
  default     = "config/dev.json"

  validation {
    condition     = fileexists(var.project_config_path)
    error_message = "project_config_path must point to an existing file."
  }
}

variable "enable_bastion_ssh_bootstrap" {
  description = "Temporarily allow direct bastion SSH on port 22 while Ansible configures the final SSH port. Disable after bootstrap."
  type        = bool
  default     = false
}

variable "secret_version_managers" {
  description = "IAM members allowed to add new versions to every secret. Adding a version does not grant reading one."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for member in var.secret_version_managers :
      can(regex("^(user|group|serviceAccount|principal|principalSet):.+$", member))
    ])
    error_message = "Each entry must be a fully qualified IAM member, for example user:name@example.com."
  }
}

variable "alert_email" {
  description = "Email address for AWS and GCP infrastructure alerts."
  type        = string
  nullable    = false
}

variable "database_mode" {
  description = "Database deployment mode. self_hosted runs PostgreSQL on the database VM; managed uses the selected cloud's managed PostgreSQL service."
  type        = string
  default     = "managed"

  validation {
    condition     = contains(["self_hosted", "managed"], var.database_mode)
    error_message = "database_mode must be self_hosted or managed."
  }
}

variable "database_name" {
  description = "PostgreSQL database used by OilScope."
  type        = string
  default     = "oil_tracker"
}

variable "database_username" {
  description = "PostgreSQL application user."
  type        = string
  default     = "oil_tracker"
}

variable "aws_database_subnet_cidrs" {
  description = "Private CIDR blocks used by the RDS DB subnet group."
  type        = list(string)
  default     = ["10.0.2.0/24", "10.0.3.0/24"]

  validation {
    condition     = length(var.aws_database_subnet_cidrs) >= 2
    error_message = "aws_database_subnet_cidrs must contain at least two CIDR blocks."
  }
}

variable "aws_enable_nat_gateway" {
  description = "Create a NAT Gateway so private AWS workload VMs can reach the internet without public IP addresses. NAT Gateway has an hourly and traffic cost."
  type        = bool
  default     = true
}

variable "aws_rds_engine_version" {
  description = "Amazon RDS PostgreSQL engine version."
  type        = string
  default     = "17"
}

variable "aws_rds_parameter_group_family" {
  description = "RDS PostgreSQL parameter group family matching aws_rds_engine_version."
  type        = string
  default     = "postgres17"
}

variable "aws_rds_instance_class" {
  description = "Amazon RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "aws_rds_allocated_storage" {
  description = "Amazon RDS allocated gp3 storage in GiB."
  type        = number
  default     = 20
}

variable "aws_rds_skip_final_snapshot" {
  description = "Skip the final RDS snapshot when the dev instance is destroyed."
  type        = bool
  default     = true
}

variable "aws_rds_final_snapshot_identifier" {
  description = "Optional final RDS snapshot identifier used when skip_final_snapshot is false."
  type        = string
  default     = null
  nullable    = true
}

variable "aws_rds_deletion_protection" {
  description = "Protect the RDS instance from deletion."
  type        = bool
  default     = false
}

variable "gcp_cloud_sql_database_version" {
  description = "Cloud SQL PostgreSQL database version."
  type        = string
  default     = "POSTGRES_17"
}

variable "gcp_cloud_sql_tier" {
  description = "Cloud SQL machine tier for the dev instance."
  type        = string
  default     = "db-f1-micro"
}

variable "gcp_cloud_sql_disk_size" {
  description = "Cloud SQL SSD size in GiB."
  type        = number
  default     = 10
}

variable "gcp_cloud_sql_deletion_protection" {
  description = "Protect the Cloud SQL instance from deletion."
  type        = bool
  default     = false
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID that owns the UI hostname. Null disables Terraform-managed UI DNS."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = (
      var.cloudflare_zone_id == null ||
      can(regex("^[0-9a-fA-F]{32}$", var.cloudflare_zone_id))
    )
    error_message = "cloudflare_zone_id must be a 32-character Cloudflare zone ID or null."
  }
}

variable "cloudflare_dns_proxied" {
  description = "Proxy the UI A record through Cloudflare."
  type        = bool
  default     = true
}

variable "cloudflare_dns_ttl" {
  description = "Cloudflare DNS TTL. Use 1 for automatic TTL; proxied records must use automatic TTL."
  type        = number
  default     = 1

  validation {
    condition = (
      var.cloudflare_dns_ttl == 1 ||
      (var.cloudflare_dns_ttl >= 60 && var.cloudflare_dns_ttl <= 86400)
    )
    error_message = "cloudflare_dns_ttl must be 1 (automatic) or between 60 and 86400 seconds."
  }
}
