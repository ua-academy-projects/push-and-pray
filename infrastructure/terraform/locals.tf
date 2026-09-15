locals {
  config = jsondecode(file(var.project_config_path))

  network_ranges = {
    for name, cidr in {
      vpc        = local.config.network.vpc_cidr
      management = local.config.network.management_subnet_cidr
      workload   = local.config.network.workload_subnet_cidr
      } : name => {
      prefix = try(tonumber(split("/", cidr)[1]), -1)
      first = try(sum([
        for index, octet in split(".", cidrhost(cidr, 0)) :
        tonumber(octet) * pow(256, 3 - index)
      ]), -1)
      last = try(sum([
        for index, octet in split(".", cidrhost(cidr, -1)) :
        tonumber(octet) * pow(256, 3 - index)
      ]), -1)
    }
  }

  default_cloud  = local.config.default_cloud
  default_region = local.config.default_region
  database_mode  = try(local.config.database_mode, "self_hosted")

  # Cross-cutting role/secret metadata; VM creation mappings live in the children.
  vms = {
    for name, vm in local.config.vms : name => merge(vm, {
      cloud = try(vm.cloud, local.default_cloud)
    })
  }

  placements = {
    for name, vm in local.vms : name => {
      cloud = vm.cloud
      provider_region = local.config.cloud_mappings.regions[
        try(vm.region, local.default_region)
      ][vm.cloud].region
      provider_zone = local.config.cloud_mappings.regions[
        try(vm.region, local.default_region)
      ][vm.cloud].zone
    }
  }

  gcp_placements = { for name, vm in local.placements : name => vm if vm.cloud == "gcp" }
  aws_placements = { for name, vm in local.placements : name => vm if vm.cloud == "aws" }

  bastion_vm = local.vms.bastion

  required_roles = ["bastion", "database", "history", "fetcher", "ui"]

  reserved_identity_labels = [
    "Name",
    "application",
    "cloud",
    "environment",
    "managed_by",
    "role",
  ]

  workload_vms = {
    for name, vm in local.vms :
    name => vm
    if vm.role != "bastion"
  }

  workload_clouds = distinct([for vm in values(local.workload_vms) : vm.cloud])
  managed_cloud   = local.database_mode == "managed" && length(local.workload_clouds) == 1 ? local.workload_clouds[0] : null
  database_name   = "oil_tracker"
  database_user   = "oil_tracker"
  database_port   = local.config.service_ports.postgresql
  rabbitmq_port   = try(local.config.service_ports.rabbitmq, 5672)
  redis_port      = local.config.service_ports.redis
  managed_database_password_secret_ids = distinct([
    for role in ["database", "history"] :
    local.config.application.secret_mappings[role].POSTGRES_PASSWORD
  ])
  redis_password_secret_ids = distinct([
    for role in ["database", "ui"] :
    local.config.application.secret_mappings[role].REDIS_PASSWORD
  ])
  managed_database_host_secret_id = "${local.resource_prefix}-database-host"
  rabbitmq_password_secret_id     = "${local.resource_prefix}-rabbitmq-password"
  redis_password_secret_id        = local.redis_password_secret_ids[0]

  aws_database_subnet_cidrs = [
    try(cidrsubnet(local.config.network.vpc_cidr, 8, 2), "0.0.0.0/32"),
    try(cidrsubnet(local.config.network.vpc_cidr, 8, 3), "0.0.0.0/32"),
  ]
  aws_database_ranges = [
    for cidr in local.aws_database_subnet_cidrs : {
      first = try(sum([
        for index, octet in split(".", cidrhost(cidr, 0)) :
        tonumber(octet) * pow(256, 3 - index)
      ]), -1)
      last = try(sum([
        for index, octet in split(".", cidrhost(cidr, -1)) :
        tonumber(octet) * pow(256, 3 - index)
      ]), -1)
    }
  ]

  gcp_project_id = try(local.config.clouds.gcp.project_id, null)

  gcp_regions = distinct([
    for vm in values(local.gcp_placements) : vm.provider_region
  ])

  gcp_zones = distinct([
    for vm in values(local.gcp_placements) : vm.provider_zone
  ])

  aws_regions = distinct([
    for vm in values(local.aws_placements) : vm.provider_region
  ])

  aws_zones = distinct([
    for vm in values(local.aws_placements) : vm.provider_zone
  ])

  gcp_region = try(local.gcp_regions[0], null)
  gcp_zone   = try(local.gcp_zones[0], null)

  aws_region = try(local.aws_regions[0], null)
  aws_zone   = try(local.aws_zones[0], null)

  resource_prefix = "${local.config.name_prefix}-${local.config.environment}"

  monitoring = {
    enabled            = try(local.config.monitoring.enabled, false)
    notification_email = try(local.config.monitoring.notification_email, "")
    cpu = {
      enabled           = try(local.config.monitoring.cpu.enabled, false)
      threshold_percent = try(local.config.monitoring.cpu.threshold_percent, 80)
      duration_minutes  = try(local.config.monitoring.cpu.duration_minutes, 5)
    }
    vm_health = {
      enabled = try(local.config.monitoring.vm_health.enabled, false)
    }
    lifecycle = {
      enabled       = try(local.config.monitoring.lifecycle.enabled, false)
      notify_states = try(local.config.monitoring.lifecycle.notify_states, [])
    }
    http_5xx = {
      enabled          = try(local.config.monitoring.http_5xx.enabled, false)
      threshold_count  = try(local.config.monitoring.http_5xx.threshold_count, 5)
      duration_minutes = try(local.config.monitoring.http_5xx.duration_minutes, 5)
    }
  }

  common_labels = merge(
    local.config.common_labels,
    {
      application = local.config.name_prefix
      environment = local.config.environment
      managed_by  = "terraform"
    },
  )
}

resource "terraform_data" "configuration_validation" {
  input = local.resource_prefix

  lifecycle {
    precondition {
      condition = length(local.gcp_placements) == 0 || (
        local.gcp_project_id != null &&
        can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", local.gcp_project_id))
      )
      error_message = "clouds.gcp.project_id must be a valid GCP project ID when any VM resolves to GCP."
    }

    precondition {
      condition = (
        contains(keys(local.config.clouds), local.default_cloud) &&
        contains(keys(local.config.cloud_mappings.regions), local.default_region)
      )
      error_message = "default_cloud must be declared in clouds and default_region must exist in cloud_mappings.regions."
    }

    precondition {
      condition = alltrue([
        for vm in values(local.vms) :
        contains(keys(local.config.clouds), vm.cloud)
      ])
      error_message = "Every effective VM cloud must have a matching declaration in clouds."
    }

    precondition {
      condition = (
        length(local.vms) == length(local.required_roles) &&
        alltrue([
          for role in local.required_roles :
          length([for vm in values(local.vms) : vm if vm.role == role]) == 1
        ])
      )
      error_message = "The application requires exactly one VM for each role: bastion, database, history, fetcher, and ui."
    }

    precondition {
      condition = alltrue([
        for name in keys(local.vms) :
        length("${local.resource_prefix}-${name}") <= 30
      ])
      error_message = "Every generated resource name must be at most 30 characters to satisfy the strictest provider limit. Shorten name_prefix or VM keys."
    }

    precondition {
      condition = alltrue(concat(
        [
          length(setintersection(
            toset(keys(local.config.common_labels)),
            toset(local.reserved_identity_labels),
          )) == 0
        ],
        [
          for vm in values(local.vms) :
          length(setintersection(
            toset(keys(try(vm.labels, {}))),
            toset(local.reserved_identity_labels),
          )) == 0
        ],
      ))
      error_message = "common_labels and VM labels must not override Terraform-managed identity keys: Name, application, cloud, environment, managed_by, or role."
    }

    precondition {
      condition = alltrue(flatten(concat(
        [[
          for key, value in local.config.common_labels :
          can(regex("^[a-z][a-z0-9_-]{0,62}$", key)) &&
          can(regex("^[a-z0-9_-]{0,63}$", value))
        ]],
        [
          for vm in values(local.vms) : [
            for key, value in try(vm.labels, {}) :
            can(regex("^[a-z][a-z0-9_-]{0,62}$", key)) &&
            can(regex("^[a-z0-9_-]{0,63}$", value))
          ]
        ],
      )))
      error_message = "User label keys and values must satisfy the provider-neutral lowercase label syntax."
    }

    precondition {
      condition = alltrue([
        for vm in values(local.vms) :
        vm.assign_public_ip == contains(["bastion", "ui"], vm.role)
      ])
      error_message = "Only bastion and ui may have public IPs, and both must have them."
    }

    precondition {
      condition = (
        length(local.gcp_placements) == 0 ||
        (length(local.gcp_regions) == 1 && length(local.gcp_zones) == 1)
      )
      error_message = "The current GCP network supports one resolved region and zone per deployment."
    }

    precondition {
      condition = (
        length(local.aws_placements) == 0 ||
        (length(local.aws_regions) == 1 && length(local.aws_zones) == 1)
      )
      error_message = "The current AWS VPC supports one resolved region and availability zone per deployment."
    }

    precondition {
      condition     = contains(["self_hosted", "managed"], local.database_mode)
      error_message = "database_mode must be either self_hosted or managed."
    }

    precondition {
      condition     = local.redis_port >= 1 && local.redis_port <= 65535
      error_message = "service_ports.redis must be between 1 and 65535."
    }

    precondition {
      condition     = local.database_mode != "managed" || local.database_port == 5432
      error_message = "Managed Cloud SQL and RDS PostgreSQL deployments require service_ports.postgresql=5432."
    }

    precondition {
      condition = local.database_mode != "managed" || local.managed_cloud != "aws" || alltrue([
        for database_range in local.aws_database_ranges :
        database_range.first >= local.network_ranges.vpc.first &&
        database_range.last <= local.network_ranges.vpc.last &&
        (database_range.last < local.network_ranges.management.first || database_range.first > local.network_ranges.management.last) &&
        (database_range.last < local.network_ranges.workload.first || database_range.first > local.network_ranges.workload.last)
      ])
      error_message = "AWS managed database subnets must fit inside network.vpc_cidr without overlapping management_subnet_cidr or workload_subnet_cidr."
    }

    precondition {
      condition = length(distinct([
        for vm in values(local.vms) : vm.cloud
        ])) == 1 && alltrue([
        for vm in values(local.vms) : vm.cloud == local.default_cloud
      ])
      error_message = "One deployment must place bastion and all workloads in default_cloud; mixed-cloud private routing is outside scope."
    }

    precondition {
      condition     = local.database_mode != "managed" || length(local.managed_database_password_secret_ids) == 1
      error_message = "database_mode=managed requires database and history to map POSTGRES_PASSWORD to the same secret ID."
    }

    precondition {
      condition     = length(local.redis_password_secret_ids) == 1
      error_message = "database and ui must map REDIS_PASSWORD to the same secret ID."
    }

    precondition {
      condition = alltrue([
        for cidr in [
          local.config.network.vpc_cidr,
          local.config.network.management_subnet_cidr,
          local.config.network.workload_subnet_cidr,
          ] : (
          can(cidrhost(cidr, 0)) &&
          length(split(".", try(cidrhost(cidr, 0), ""))) == 4 &&
          try(cidrhost(cidr, 0), "") == try(split("/", cidr)[0], "")
        )
      ])
      error_message = "All network CIDRs must be canonical IPv4 ranges (the address before '/' must be the network address)."
    }

    precondition {
      condition = (
        local.network_ranges.management.first >= local.network_ranges.vpc.first &&
        local.network_ranges.management.last <= local.network_ranges.vpc.last &&
        local.network_ranges.workload.first >= local.network_ranges.vpc.first &&
        local.network_ranges.workload.last <= local.network_ranges.vpc.last
      )
      error_message = "Management and workload subnets must be fully contained in network.vpc_cidr."
    }

    precondition {
      condition = (
        local.network_ranges.management.last < local.network_ranges.workload.first ||
        local.network_ranges.workload.last < local.network_ranges.management.first
      )
      error_message = "Management and workload subnet CIDRs must not overlap."
    }
  }
}

locals {
  firewall_policy = {
    bastion_ssh_port      = local.bastion_vm.ssh_port
    bastion_allowed_cidrs = local.bastion_vm.allowed_cidrs
    history_api_port      = local.config.service_ports.history_api
    postgresql_port       = local.config.service_ports.postgresql
    postgresql_enabled    = local.database_mode == "self_hosted"
    rabbitmq_port         = local.rabbitmq_port
    rabbitmq_enabled      = local.database_mode == "managed"
    redis_port            = local.redis_port
    ui_public_ports       = local.config.network.ui_public_ports
  }
}

locals {
  startup_scripts = {
    bastion = templatefile("${path.module}/templates/ssh-bootstrap.sh.tftpl", {
      ssh_port = local.bastion_vm.ssh_port
    })
  }
}
