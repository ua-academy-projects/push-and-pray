# public entry point: ssh to bastion from approved sources

resource "google_compute_firewall" "bastion_ssh_ingress" {
  project     = var.project_id
  name        = "${local.prefix}-allow-ssh-to-bastion"
  description = "Ingress SSH on port ${var.ssh_port} to the bastion from approved source ranges only."

  network   = google_compute_network.vpc.id
  direction = "INGRESS"
  priority  = 1000

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

}

# public entry point: http/https to the ui service
#
# The UI instance itself is created by the compute work (issue #14). This rule is
# the network-side contract for it: whatever that instance turns out to be, it
# becomes publicly reachable on ui_public_ports the moment it carries the
# <name_prefix>-ui tag, and on nothing else. Ingress in GCP selects targets by
# tag, not by destination range, so no IP has to be known here in advance.

resource "google_compute_firewall" "ui_public_ingress" {
  count = var.enable_ui_public_ingress ? 1 : 0

  project     = var.project_id
  name        = "${local.prefix}-allow-ui-public"
  description = "Ingress ${join(",", var.ui_public_ports)} from ${join(",", var.ui_source_ranges)} to instances tagged ${local.tag_ui}. The only intentionally public service."

  network   = google_compute_network.vpc.id
  direction = "INGRESS"
  priority  = 1000

  source_ranges = var.ui_source_ranges
  target_tags   = [local.tag_ui]

  allow {
    protocol = "tcp"
    ports    = var.ui_public_ports
  }

  dynamic "log_config" {
    for_each = local.firewall_log_config

    content {
      metadata = "INCLUDE_ALL_METADATA"
    }
  }

  lifecycle {
    # The public rule must never become a way in to an internal port. If the UI
    # ever needs to serve on an application port, put a reverse proxy in front of
    # it instead of widening this rule.
    precondition {
      condition = length(setintersection(
        toset(var.ui_public_ports),
        toset([tostring(var.history_api_port), tostring(var.db_port)])
      )) == 0
      error_message = "ui_public_ports must not contain History API or PostgreSQL ports."
    }
  }
}

# ssh to private instances only from bastion

resource "google_compute_firewall" "ssh_from_bastion" {
  project     = var.project_id
  name        = "${local.prefix}-allow-ssh-from-bastion"
  description = "Ingress SSH on port ${var.ssh_port} to workload instances, only from the bastion role."

  network   = google_compute_network.vpc.id
  direction = "INGRESS"
  priority  = 1000

  source_tags = [local.tag_bastion]
  target_tags = local.workload_tags

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

# History API: UI is its only cross-VM client.

resource "google_compute_firewall" "history_api_from_ui" {
  project     = var.project_id
  name        = "${local.prefix}-allow-history-api-from-ui"
  description = "Ingress to the History API from the UI workload only."

  network   = google_compute_network.vpc.id
  direction = "INGRESS"
  priority  = 1000

  source_tags = [local.tag_ui]
  target_tags = [local.tag_history]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.history_api_port)]
  }

  dynamic "log_config" {
    for_each = local.firewall_log_config

    content {
      metadata = "INCLUDE_ALL_METADATA"
    }
  }

}

# PostgreSQL on Infra is used directly by Fetcher and History.

resource "google_compute_firewall" "postgresql_to_infra" {
  project     = var.project_id
  name        = "${local.prefix}-allow-postgresql-to-infra"
  description = "Ingress to PostgreSQL on Infra from Fetcher and History only."

  network   = google_compute_network.vpc.id
  direction = "INGRESS"
  priority  = 1000

  source_tags = [local.tag_fetcher, local.tag_history]
  target_tags = [local.tag_infra]

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
  target_tags   = concat([local.tag_bastion], local.workload_tags)

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
# egress: least privilege outbound, opt-in via restrict_egress
#
# GCP's implied egress rule allows everything. These rules override it: a
# catch-all deny at priority 65534 plus narrow allows above it. Cloud NAT still
# provides the path to the internet - these rules decide what is allowed to use it.

resource "google_compute_firewall" "egress_internal" {
  count = var.restrict_egress ? 1 : 0

  project     = var.project_id
  name        = "${local.prefix}-allow-egress-internal"
  description = "Egress between instances inside the VPC."

  network   = google_compute_network.vpc.id
  direction = "EGRESS"
  priority  = 1000

  destination_ranges = local.internal_ranges

  allow {
    protocol = "all"
  }

  dynamic "log_config" {
    for_each = local.firewall_log_config

    content {
      metadata = "INCLUDE_ALL_METADATA"
    }
  }
}

resource "google_compute_firewall" "egress_metadata_server" {
  count = var.restrict_egress ? 1 : 0

  project     = var.project_id
  name        = "${local.prefix}-allow-egress-metadata"
  description = "Egress to the GCE metadata server: DNS, instance metadata and SSH key propagation depend on it."

  network   = google_compute_network.vpc.id
  direction = "EGRESS"
  priority  = 1000

  destination_ranges = ["169.254.169.254/32"]

  allow {
    protocol = "tcp"
    ports    = ["80", "53"]
  }

  allow {
    protocol = "udp"
    ports    = ["53"]
  }
}

resource "google_compute_firewall" "egress_dns_ntp" {
  count = var.restrict_egress ? 1 : 0

  project     = var.project_id
  name        = "${local.prefix}-allow-egress-dns-ntp"
  description = "Egress DNS and NTP. Without these an instance cannot resolve names or keep its clock, which breaks TLS."

  network   = google_compute_network.vpc.id
  direction = "EGRESS"
  priority  = 1000

  destination_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "udp"
    ports    = ["53", "123"]
  }

  allow {
    protocol = "tcp"
    ports    = ["53"]
  }
}

resource "google_compute_firewall" "egress_internet" {
  count = var.restrict_egress ? 1 : 0

  project     = var.project_id
  name        = "${local.prefix}-allow-egress-internet"
  description = "Egress to the internet on ${join(",", var.egress_allowed_ports)} only: package repositories, container registries and the upstream price API."

  network   = google_compute_network.vpc.id
  direction = "EGRESS"
  priority  = 1000

  destination_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "tcp"
    ports    = var.egress_allowed_ports
  }

  dynamic "log_config" {
    for_each = local.firewall_log_config

    content {
      metadata = "INCLUDE_ALL_METADATA"
    }
  }
}

resource "google_compute_firewall" "deny_all_egress" {
  count = var.restrict_egress ? 1 : 0

  project     = var.project_id
  name        = "${local.prefix}-deny-all-egress"
  description = "Explicit catch-all egress deny. Overrides the permissive implied egress rule."

  network   = google_compute_network.vpc.id
  direction = "EGRESS"
  priority  = 65534

  destination_ranges = ["0.0.0.0/0"]

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
