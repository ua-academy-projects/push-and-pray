# public entry point: ssh to bastion from approved sources

resource "google_compute_firewall" "bastion_ssh_ingress" {
  project     = var.project_id
  name        = "${local.prefix}-allow-ssh-to-bastion"
  description = "Ingress SSH on port ${var.ssh_port} to the bastion from approved source ranges only."

  network   = google_compute_network.vpc.id
  direction = "INGRESS"
  priority  = 1000

  # Validated in variables.tf: 0.0.0.0/0 and anything broader than /8 is rejected.
  source_ranges = var.bastion_allowed_cidrs
  target_tags   = [local.tag_bastion]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.ssh_port)]
  }

  dynamic "log_config" {
    for_each = local.firewall_log_config

    content {
      metadata = "INCLUDE_ALL_METADATA"
    }
  }

  lifecycle {
    precondition {
      condition     = !contains([for c in var.bastion_allowed_cidrs : trimspace(c)], "0.0.0.0/0")
      error_message = "Refusing to create an unrestricted public SSH rule: bastion_allowed_cidrs contains 0.0.0.0/0."
    }
  }
}

# ssh to private instances only from bastion

resource "google_compute_firewall" "ssh_from_bastion" {
  project     = var.project_id
  name        = "${local.prefix}-allow-ssh-from-bastion"
  description = "Ingress SSH on port ${var.ssh_port} to private instances, only from instances tagged ${local.tag_bastion}."

  network   = google_compute_network.vpc.id
  direction = "INGRESS"
  priority  = 1000

  source_tags = [local.tag_bastion]
  target_tags = [local.tag_app, local.tag_db]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.ssh_port)]
  }

  dynamic "log_config" {
    for_each = local.firewall_log_config

    content {
      metadata = "INCLUDE_ALL_METADATA"
    }
  }
}

# application ports: only internal

resource "google_compute_firewall" "app_internal" {
  project     = var.project_id
  name        = "${local.prefix}-allow-app-internal"
  description = "Ingress to application ports ${join(",", var.app_ports)} from inside the VPC only. Never from the internet."

  network   = google_compute_network.vpc.id
  direction = "INGRESS"
  priority  = 1000

  source_ranges = local.internal_ranges
  target_tags   = [local.tag_app]

  allow {
    protocol = "tcp"
    ports    = var.app_ports
  }

  dynamic "log_config" {
    for_each = local.firewall_log_config

    content {
      metadata = "INCLUDE_ALL_METADATA"
    }
  }

  lifecycle {
    precondition {
      condition     = !contains(var.app_ports, tostring(var.db_port))
      error_message = "db_port must not appear in app_ports, otherwise the database port would inherit the broader application sources."
    }
  }
}

# db port
# No source_ranges at all. The only way to reach the database port is to be an
# instance tagged as an application server. The bastion is deliberately NOT a
# source here: an operator SSHes into an app host first, or port-forwards through
# the bastion, which is logged.

resource "google_compute_firewall" "db_from_app" {
  project     = var.project_id
  name        = "${local.prefix}-allow-db-from-app"
  description = "Ingress to database port ${var.db_port} from instances tagged ${local.tag_app} only. Not reachable from the internet."

  network   = google_compute_network.vpc.id
  direction = "INGRESS"
  priority  = 1000

  source_tags = [local.tag_app]
  target_tags = [local.tag_db]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.db_port)]
  }

  dynamic "log_config" {
    for_each = local.firewall_log_config

    content {
      metadata = "INCLUDE_ALL_METADATA"
    }
  }
}

# internal ICMP

resource "google_compute_firewall" "internal_icmp" {
  project     = var.project_id
  name        = "${local.prefix}-allow-internal-icmp"
  description = "ICMP inside the VPC for connectivity troubleshooting."

  network   = google_compute_network.vpc.id
  direction = "INGRESS"
  priority  = 1000

  source_ranges = local.internal_ranges
  target_tags   = [local.tag_bastion, local.tag_app, local.tag_db]

  allow {
    protocol = "icmp"
  }
}

# explicit all ingress deny

resource "google_compute_firewall" "deny_all_ingress" {
  project     = var.project_id
  name        = "${local.prefix}-deny-all-ingress"
  description = "Explicit catch-all ingress deny. Anything not matched by a rule above lands here."

  network   = google_compute_network.vpc.id
  direction = "INGRESS"
  priority  = 65533

  source_ranges = ["0.0.0.0/0"]

  deny {
    protocol = "all"
  }

  dynamic "log_config" {
    for_each = local.firewall_deny_log_config

    content {
      metadata = "INCLUDE_ALL_METADATA"
    }
  }
}