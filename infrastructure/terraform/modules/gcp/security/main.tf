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

# A workload's remote-cloud destination is retained while the packet enters
# the next-hop bastion. This explicit rule permits GCP workload-to-router
# transit; without it, the VPC implied ingress deny drops the packet.
resource "google_compute_firewall" "workload_to_tailscale_bastion" {
  name    = "${var.resource_prefix}-allow-k3s-transit-to-bastion"
  network = var.network_id

  source_ranges = [var.k3s_node_cidr]
  target_tags   = [local.network_tags.bastion]

  allow {
    protocol = "tcp"
    ports    = ["6443", "10250", "2379", "2380"]
  }

  allow {
    protocol = "udp"
    ports    = ["8472"]
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
    local.network_tags.k3s_server,
    local.network_tags.k3s_agent,
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

resource "google_compute_firewall" "k3s_ingress" {
  name    = "${var.resource_prefix}-allow-k3s-ingress"
  network = var.network_id

  source_ranges = ["0.0.0.0/0"]
  target_tags   = [local.network_tags.k3s_server]

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
}

resource "google_compute_firewall" "k3s_api" {
  name    = "${var.resource_prefix}-allow-k3s-api"
  network = var.network_id

  source_ranges = var.bastion_allowed_cidrs
  target_tags   = [local.network_tags.k3s_server]

  allow {
    protocol = "tcp"
    ports    = ["6443"]
  }
}

resource "google_compute_firewall" "k3s_internal" {
  name    = "${var.resource_prefix}-allow-k3s-internal"
  network = var.network_id

  source_tags = [local.network_tags.k3s_server, local.network_tags.k3s_agent]
  target_tags = [local.network_tags.k3s_server, local.network_tags.k3s_agent]

  allow {
    protocol = "tcp"
    ports    = ["6443", "10250"]
  }

  allow {
    protocol = "udp"
    ports    = ["8472"]
  }
}

# Embedded etcd is the K3s control-plane datastore. Its peer and client ports
# must be reachable between server nodes, but never from agent nodes.
resource "google_compute_firewall" "k3s_etcd" {
  name    = "${var.resource_prefix}-allow-k3s-etcd"
  network = var.network_id

  source_tags = [local.network_tags.k3s_server]
  target_tags = [local.network_tags.k3s_server]

  allow {
    protocol = "tcp"
    ports    = ["2379", "2380"]
  }
}

# Subnet-router SNAT is disabled, so embedded etcd sees the source IP recorded
# in each remote peer's certificate rather than a local bastion address.
resource "google_compute_firewall" "tailscale_router_to_k3s" {
  name    = "${var.resource_prefix}-allow-tailscale-router-k3s"
  network = var.network_id

  source_ranges = var.k3s_remote_node_cidrs
  target_tags   = [local.network_tags.k3s_server]

  allow {
    protocol = "tcp"
    ports    = ["6443", "10250", "2379", "2380"]
  }

  allow {
    protocol = "udp"
    ports    = ["8472"]
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
