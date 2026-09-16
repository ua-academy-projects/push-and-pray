resource "google_compute_firewall" "bastion_ssh" {
  name    = "${var.resource_prefix}-allow-bastion-ssh"
  network = var.network_id

  source_ranges = var.bastion_allowed_cidrs
  target_tags   = [local.network_tags.bastion]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.bastion_ssh_port)]
  }
}

resource "google_compute_firewall" "bastion_ssh_bootstrap" {
  count = var.enable_bastion_ssh_bootstrap && var.bastion_ssh_port != 22 ? 1 : 0

  name    = "${var.resource_prefix}-allow-bastion-ssh-bootstrap"
  network = var.network_id

  source_ranges = var.bastion_allowed_cidrs
  target_tags   = [local.network_tags.bastion]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "workload_ssh" {
  name    = "${var.resource_prefix}-allow-workload-ssh"
  network = var.network_id

  source_tags = [local.network_tags.bastion]
  target_tags = [
    local.network_tags.infra,
    local.network_tags.history,
    local.network_tags.fetcher,
    local.network_tags.ui,
  ]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "ui_web" {
  name    = "${var.resource_prefix}-allow-ui-web"
  network = var.network_id

  source_ranges = ["0.0.0.0/0"]
  target_tags   = [local.network_tags.ui]

  allow {
    protocol = "tcp"
    ports    = var.ui_public_ports
  }
}

resource "google_compute_firewall" "history_api" {
  name    = "${var.resource_prefix}-allow-history-api"
  network = var.network_id

  source_tags = [local.network_tags.ui]
  target_tags = [local.network_tags.history]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.history_api_port)]
  }
}

resource "google_compute_firewall" "postgresql" {
  count = var.managed_mode ? 0 : 1

  name    = "${var.resource_prefix}-allow-postgresql"
  network = var.network_id

  source_tags = [
    local.network_tags.fetcher,
    local.network_tags.history,
    local.network_tags.ui,
  ]
  target_tags = [local.network_tags.infra]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.postgresql_port)]
  }
}

resource "google_compute_firewall" "rabbitmq" {
  count = var.managed_mode ? 1 : 0

  name    = "${var.resource_prefix}-allow-rabbitmq"
  network = var.network_id

  source_tags = [local.network_tags.fetcher, local.network_tags.history]
  target_tags = [local.network_tags.infra]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.rabbitmq_port)]
  }
}

resource "google_compute_firewall" "redis" {
  count = var.managed_mode ? 1 : 0

  name    = "${var.resource_prefix}-allow-redis"
  network = var.network_id

  source_tags = [local.network_tags.ui]
  target_tags = [local.network_tags.infra]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.redis_port)]
  }
}

# Only History owns PostgreSQL access in managed mode. Fetcher publishes to
# RabbitMQ and UI stores sessions in Redis, so the remaining project VMs have
# no reason to establish a TCP connection to Cloud SQL.
resource "google_compute_firewall" "deny_non_history_to_managed_database" {
  count = var.managed_mode ? 1 : 0

  name               = "${var.resource_prefix}-deny-managed-postgresql"
  network            = var.network_id
  direction          = "EGRESS"
  priority           = 900
  destination_ranges = ["${var.managed_database_host}/32"]
  target_tags = [
    local.network_tags.bastion,
    local.network_tags.infra,
    local.network_tags.fetcher,
    local.network_tags.ui,
  ]

  deny {
    protocol = "tcp"
    ports    = [tostring(var.postgresql_port)]
  }
}
