resource "google_compute_firewall" "bastion_ssh" {
  name    = "${var.resource_prefix}-allow-bastion-ssh"
  network = var.network_id

  source_ranges = var.bastion.allowed_cidrs
  target_tags   = [local.network_tags.bastion]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.bastion.ssh_port)]
  }
}

resource "google_compute_firewall" "bastion_ssh_bootstrap" {
  count = var.enable_bastion_ssh_bootstrap && var.bastion.ssh_port != 22 ? 1 : 0

  name    = "${var.resource_prefix}-allow-bastion-ssh-bootstrap"
  network = var.network_id

  source_ranges = var.bastion.allowed_cidrs
  target_tags   = [local.network_tags.bastion]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# Direct WireGuard connections between tailnet devices. Without it Tailscale
# still works, relayed through DERP and noticeably slower.
resource "google_compute_firewall" "bastion_tailscale" {
  name    = "${var.resource_prefix}-allow-bastion-tailscale"
  network = var.network_id

  source_ranges = ["0.0.0.0/0"]
  target_tags   = [local.network_tags.bastion]

  allow {
    protocol = "udp"
    ports    = [tostring(var.tailscale.port)]
  }
}

# A packet a node sends to another cloud or to the tailnet is routed to the
# bastion, and the firewall checks it on the way in - addressed to someone
# else, but arriving at the bastion all the same.
resource "google_compute_firewall" "bastion_forwarding" {
  name    = "${var.resource_prefix}-allow-bastion-forwarding"
  network = var.network_id

  source_ranges = [var.network_cidr]
  target_tags   = [local.network_tags.bastion]

  allow {
    protocol = "all"
  }
}

# Ansible reaches the nodes over the tailnet, which arrives with a tailnet
# source address; from the bastion itself it is the fallback.
resource "google_compute_firewall" "node_ssh" {
  name    = "${var.resource_prefix}-allow-node-ssh"
  network = var.network_id

  source_tags   = [local.network_tags.bastion]
  source_ranges = [var.tailscale.address_range]
  target_tags   = local.node_tags

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "cluster" {
  for_each = local.cluster_ports

  name    = "${var.resource_prefix}-allow-${each.key}"
  network = var.network_id

  source_ranges = var.cluster_cidrs
  target_tags   = [for role in each.value.roles : local.network_tags[role]]

  allow {
    protocol = each.value.protocol
    ports    = [for port in each.value.ports : tostring(port)]
  }
}

# Path MTU discovery needs ICMP: the tunnel between the clouds carries smaller
# packets than the networks on either side, and without "fragmentation
# needed" coming back large packets vanish silently. It also makes ping work.
resource "google_compute_firewall" "cluster_icmp" {
  name    = "${var.resource_prefix}-allow-cluster-icmp"
  network = var.network_id

  source_ranges = var.cluster_cidrs
  target_tags   = concat(local.node_tags, [local.network_tags.bastion])

  allow {
    protocol = "icmp"
  }
}

resource "google_compute_firewall" "ingress_web" {
  name    = "${var.resource_prefix}-allow-ingress-web"
  network = var.network_id

  source_ranges = ["0.0.0.0/0"]
  target_tags   = [local.network_tags.ingress]

  allow {
    protocol = "tcp"
    ports    = [for port in var.cluster.ingress.public_ports : tostring(port)]
  }
}
