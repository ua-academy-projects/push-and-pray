resource "google_compute_firewall" "bastion_ssh" {
  count   = length(local.vms) > 0 ? 1 : 0
  name    = "${local.resource_prefix}-allow-bastion-ssh"
  network = var.network_id

  source_ranges = lookup(local.bastion, "allowed_cidrs", ["127.0.0.1/32"])
  target_tags   = [local.network_tags.bastion]

  allow {
    protocol = "tcp"
    ports    = [tostring(lookup(local.bastion, "ssh_port", 22))]
  }
}

resource "google_compute_firewall" "bastion_ssh_bootstrap" {
  # A fresh bastion listens on 22 until Ansible installs the final sshd policy.
  # This rule must be explicitly enabled and removed immediately after bootstrap.
  count = length(local.bastion) > 0 && var.enable_bastion_ssh_bootstrap && lookup(local.bastion, "ssh_port", 22) != 22 ? 1 : 0

  name    = "${local.resource_prefix}-allow-bastion-ssh-bootstrap"
  network = var.network_id

  source_ranges = lookup(local.bastion, "allowed_cidrs", ["127.0.0.1/32"])
  target_tags   = [local.network_tags.bastion]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "workload_ssh" {
  count   = length(local.vms) > 0 ? 1 : 0
  name    = "${local.resource_prefix}-allow-workload-ssh"
  network = var.network_id

  source_tags = [local.network_tags.bastion, local.network_tags.k3s]
  target_tags = [
    local.network_tags.infra,
    local.network_tags.history,
    local.network_tags.fetcher,
    local.network_tags.ui,
    local.network_tags.k3s,
  ]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "ui_web" {
  count   = length(local.vms) > 0 ? 1 : 0
  name    = "${local.resource_prefix}-allow-ui-web"
  network = var.network_id

  source_ranges = ["0.0.0.0/0"]
  target_tags = [
    local.network_tags.ui,
    local.network_tags["k3s-ingress"],
  ]

  allow {
    protocol = "tcp"
    ports    = [for port in var.config.network.ui_public_ports : tostring(port)]
  }
}

resource "google_compute_firewall" "history_api" {
  count   = length(local.vms) > 0 ? 1 : 0
  name    = "${local.resource_prefix}-allow-history-api"
  network = var.network_id

  source_tags = [local.network_tags.ui]
  target_tags = [local.network_tags.history]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.config.service_ports.history_api)]
  }
}

resource "google_compute_firewall" "postgresql" {
  count   = length(local.vms) > 0 && var.database_mode == "self_hosted" ? 1 : 0
  name    = "${local.resource_prefix}-allow-postgresql"
  network = var.network_id

  source_tags = [
    local.network_tags.fetcher,
    local.network_tags.history,
    local.network_tags.ui,
  ]

  target_tags = [local.network_tags.infra]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.config.service_ports.postgresql)]
  }
}


resource "google_compute_firewall" "rabbitmq" {
  count = length(local.vms) > 0 && var.database_mode == "managed" ? 1 : 0

  name    = "${local.resource_prefix}-allow-rabbitmq"
  network = var.network_id

  source_tags = [
    local.network_tags.fetcher,
    local.network_tags.history,
  ]
  target_tags = [local.network_tags.infra]

  allow {
    protocol = "tcp"
    ports    = [tostring(try(var.config.service_ports.rabbitmq, 5672))]
  }
}


resource "google_compute_firewall" "k3s_api" {
  count   = length(local.k3s_servers) > 0 ? 1 : 0
  name    = "${local.resource_prefix}-allow-k3s-api"
  network = var.network_id

  source_tags = [local.network_tags.k3s, local.network_tags.bastion]
  target_tags = [local.network_tags["k3s-server"]]

  allow {
    protocol = "tcp"
    ports    = ["6443"]
  }
}

resource "google_compute_firewall" "k3s_etcd" {
  count   = length(local.k3s_servers) > 0 ? 1 : 0
  name    = "${local.resource_prefix}-allow-k3s-etcd"
  network = var.network_id

  source_tags = [local.network_tags["k3s-server"], local.network_tags.bastion]
  target_tags = [local.network_tags["k3s-server"]]

  allow {
    protocol = "tcp"
    ports    = ["2379-2380"]
  }
}

resource "google_compute_firewall" "k3s_flannel_vxlan" {
  count   = length(local.k3s_nodes) > 0 ? 1 : 0
  name    = "${local.resource_prefix}-allow-k3s-flannel-vxlan"
  network = var.network_id

  source_tags = [local.network_tags.k3s, local.network_tags.bastion]
  target_tags = [local.network_tags.k3s]

  allow {
    protocol = "udp"
    ports    = ["8472"]
  }
}

resource "google_compute_firewall" "k3s_kubelet" {
  count   = length(local.k3s_nodes) > 0 ? 1 : 0
  name    = "${local.resource_prefix}-allow-k3s-kubelet"
  network = var.network_id

  source_tags = [local.network_tags.k3s, local.network_tags.bastion]
  target_tags = [local.network_tags.k3s]

  allow {
    protocol = "tcp"
    ports    = ["10250"]
  }
}
