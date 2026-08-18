# variables related to project and naming

variable "project_id" {
  description = "GCP project ID where all resources are created."
  type        = string
}

variable "region" {
  description = "Primary region for the subnets, Cloud Router and Cloud NAT."
  type        = string
  default     = "europe-central2"
}

variable "name_prefix" {
  description = "Prefix for every resource name. Keep it short: GCP names are limited to 63 chars."
  type        = string
  default     = "oil"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.name_prefix))
    error_message = "name_prefix must start with a lowercase letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "labels" {
  description = "Labels applied to every resource that supports them."
  type        = map(string)
  default     = {}
}

# variables related to network and subnets

variable "public_subnet_cidr" {
  description = "CIDR of the public subnet. The bastion and the public-facing UI instance live here."
  type        = string
  default     = "10.10.0.0/24"

  validation {
    condition     = can(cidrhost(var.public_subnet_cidr, 0))
    error_message = "public_subnet_cidr must be a valid IPv4 CIDR block."
  }
}

variable "private_subnet_cidr" {
  description = "CIDR of the private subnet. Application and database instances live here and never get an external IP."
  type        = string
  default     = "10.10.1.0/24"

  validation {
    condition     = can(cidrhost(var.private_subnet_cidr, 0))
    error_message = "private_subnet_cidr must be a valid IPv4 CIDR block."
  }
}

variable "private_secondary_ranges" {
  description = <<-EOT
    Optional secondary ranges on the private subnet (e.g. GKE pods/services).
    Example: { pods = "10.20.0.0/16", services = "10.21.0.0/20" }
  EOT
  type        = map(string)
  default     = {}
}

variable "routing_mode" {
  description = "VPC dynamic routing mode: REGIONAL or GLOBAL."
  type        = string
  default     = "REGIONAL"

  validation {
    condition     = contains(["REGIONAL", "GLOBAL"], var.routing_mode)
    error_message = "routing_mode must be REGIONAL or GLOBAL."
  }
}

variable "mtu" {
  description = "VPC MTU. 1460 is the GCP default"
  type        = number
  default     = 1460
}

variable "manage_default_route" {
  description = <<-EOT
    When true, the auto-created default route is deleted at network creation time and
    replaced by an explicitly managed 0.0.0.0/0 -> default-internet-gateway route.
    Routing then lives entirely in code and shows up in the plan. Egress is still
    controlled by firewall rules, not by this route.
  EOT
  type        = bool
  default     = true
}

# variables for cloud nat

variable "enable_nat" {
  description = "Create Cloud Router + Cloud NAT so private instances get egress-only internet access."
  type        = bool
  default     = true
}

variable "nat_static_ip_count" {
  description = <<-EOT
    Number of static external IPs to reserve for Cloud NAT.
    0 = AUTO_ONLY (Google picks ephemeral IPs).
    >0 = MANUAL_ONLY, which gives you a stable egress IP set you can hand to third parties for allow-listing.
  EOT
  type        = number
  default     = 0

  validation {
    condition     = var.nat_static_ip_count >= 0 && var.nat_static_ip_count <= 8
    error_message = "nat_static_ip_count must be between 0 and 8."
  }
}

variable "nat_log_filter" {
  description = "Cloud NAT logging filter: ERRORS_ONLY, TRANSLATIONS_ONLY or ALL."
  type        = string
  default     = "ERRORS_ONLY"

  validation {
    condition     = contains(["ERRORS_ONLY", "TRANSLATIONS_ONLY", "ALL"], var.nat_log_filter)
    error_message = "nat_log_filter must be ERRORS_ONLY, TRANSLATIONS_ONLY or ALL."
  }
}

# variables for ssh access

variable "ssh_port" {
  description = "Non-default SSH port. Used both in the firewall rules here and in the sshd configuration of the bastion module."
  type        = number
  default     = 18832

  validation {
    condition     = var.ssh_port >= 1024 && var.ssh_port <= 65535 && var.ssh_port != 22
    error_message = "ssh_port must be in the 1024-65535 range and must not be the default port 22."
  }
}

variable "bastion_allowed_cidrs" {
  description = <<-EOT
    Source CIDRs allowed to reach the bastion on ssh_port. Office ranges / VPN egress IPs only.
    Unrestricted access (0.0.0.0/0, ::/0, or anything broader than /8) is rejected.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.bastion_allowed_cidrs) > 0
    error_message = "bastion_allowed_cidrs must contain at least one CIDR: the bastion is useless without an allowed source."
  }

  validation {
    condition = alltrue([
      for c in var.bastion_allowed_cidrs : can(cidrhost(c, 0))
    ])
    error_message = "Every entry in bastion_allowed_cidrs must be a valid IPv4 CIDR block (e.g. 203.0.113.10/32)."
  }

  validation {
    condition = alltrue([
      for c in var.bastion_allowed_cidrs :
      !contains(["0.0.0.0/0", "::/0"], trimspace(c)) && try(tonumber(split("/", c)[1]) >= 8, false)
    ])
    error_message = "Unrestricted public SSH is not allowed: remove 0.0.0.0/0 (and any prefix shorter than /8) from bastion_allowed_cidrs."
  }
}

# variables related to application / db ports

variable "app_ports" {
  description = "Internal application ports, reachable only from inside the VPC. Never from the internet."
  type        = list(string)
  default     = ["8080", "5672", "6379", "15672"]

  validation {
    condition     = length(var.app_ports) > 0
    error_message = "app_ports must not be empty."
  }
}

variable "db_port" {
  description = "Database port. Reachable only from instances carrying the application tag."
  type        = number
  default     = 5432
}

variable "enable_ui_public_ingress" {
  description = "Create the public HTTP/HTTPS ingress rule for instances tagged <name_prefix>-ui."
  type        = bool
  default     = true
}

variable "ui_public_ports" {
  description = <<-EOT
    TCP ports the UI service exposes to the internet. 80 is kept so the UI can
    redirect to HTTPS and so ACME HTTP-01 challenges work.
    Application and database ports must never appear here.
  EOT
  type        = list(string)
  default     = ["80", "443"]

  validation {
    condition     = !var.enable_ui_public_ingress || length(var.ui_public_ports) > 0
    error_message = "ui_public_ports must not be empty when enable_ui_public_ingress is true."
  }
}

variable "ui_source_ranges" {
  description = <<-EOT
    Source ranges allowed to reach ui_public_ports. 0.0.0.0/0 on purpose: this is
    the public web entry point. Narrow it while the UI is not meant to be public yet.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition = alltrue([
      for c in var.ui_source_ranges : can(cidrhost(c, 0))
    ])
    error_message = "Every entry in ui_source_ranges must be a valid IPv4 CIDR block."
  }
}

# variables related to firewall behavior

variable "enable_firewall_logging" {
  description = "Enable firewall rule logging on the allow rules. Strongly recommended: this is what proves who connected."
  type        = bool
  default     = true
}

variable "log_denied_traffic" {
  description = "Also log the explicit low-priority deny rules. Very useful while debugging, noisy and costly in steady state."
  type        = bool
  default     = false
}

variable "restrict_egress" {
  description = <<-EOT
    When true, the permissive implied egress rule is overridden by a deny-all egress rule plus
    narrow allows (DNS, NTP, the metadata server, egress_allowed_ports and in-VPC traffic).
    Genuine least privilege, but it will break anything that talks to an unexpected endpoint -
    roll it out in a non-production project first.
  EOT
  type        = bool
  default     = false
}

variable "egress_allowed_ports" {
  description = "TCP ports allowed outbound to the internet when restrict_egress is true."
  type        = list(string)
  default     = ["443"]

  validation {
    condition     = !var.restrict_egress || length(var.egress_allowed_ports) > 0
    error_message = "egress_allowed_ports must not be empty when restrict_egress is true."
  }
}
