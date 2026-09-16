locals {
  mixed_aws_cidr = local.mixed_network_enabled ? module.aws.network.vpc_cidr : null
  mixed_gcp_cidr = local.mixed_network_enabled ? module.gcp.network.vpc_cidr : null
  mixed_gcp_database_cidr = (
    local.mixed_network_enabled &&
    local.manage_db &&
    lower(local.root_config.database.cloud) == "gcp"
    ) ? merge(
    local.root_config.network,
    try(local.root_config.clouds.gcp.network, {}),
  ).database_private_service_cidr : null
  mixed_aws_database_enabled = (
    local.mixed_network_enabled &&
    local.manage_db &&
    lower(local.root_config.database.cloud) == "aws"
  )

  aws_vpn_destinations = local.mixed_network_enabled ? merge(
    { gcp_vpc = local.mixed_gcp_cidr },
    local.mixed_gcp_database_cidr == null ? {} : {
      gcp_database = local.mixed_gcp_database_cidr
    },
  ) : {}
}

resource "google_compute_address" "mixed_vpn" {
  count = local.mixed_network_enabled ? 1 : 0

  name         = "${local.root_config.name_prefix}-${local.root_config.environment}-mixed-vpn"
  region       = module.gcp.network.region
  address_type = "EXTERNAL"
}

resource "google_compute_vpn_gateway" "mixed" {
  count = local.mixed_network_enabled ? 1 : 0

  name    = "${local.root_config.name_prefix}-${local.root_config.environment}-mixed-vpn"
  network = module.gcp.network.network_id
  region  = module.gcp.network.region
}

resource "google_compute_forwarding_rule" "mixed_esp" {
  count = local.mixed_network_enabled ? 1 : 0

  name        = "${local.root_config.name_prefix}-${local.root_config.environment}-mixed-esp"
  region      = module.gcp.network.region
  ip_address  = google_compute_address.mixed_vpn[0].address
  ip_protocol = "ESP"
  target      = google_compute_vpn_gateway.mixed[0].id
}

resource "google_compute_forwarding_rule" "mixed_udp500" {
  count = local.mixed_network_enabled ? 1 : 0

  name        = "${local.root_config.name_prefix}-${local.root_config.environment}-mixed-udp500"
  region      = module.gcp.network.region
  ip_address  = google_compute_address.mixed_vpn[0].address
  ip_protocol = "UDP"
  port_range  = "500"
  target      = google_compute_vpn_gateway.mixed[0].id
}

resource "google_compute_forwarding_rule" "mixed_udp4500" {
  count = local.mixed_network_enabled ? 1 : 0

  name        = "${local.root_config.name_prefix}-${local.root_config.environment}-mixed-udp4500"
  region      = module.gcp.network.region
  ip_address  = google_compute_address.mixed_vpn[0].address
  ip_protocol = "UDP"
  port_range  = "4500"
  target      = google_compute_vpn_gateway.mixed[0].id
}

resource "aws_vpn_gateway" "mixed" {
  count = local.mixed_network_enabled ? 1 : 0

  vpc_id = module.aws.network.vpc_id
  tags = merge(module.aws.network == null ? {} : {
    Name = "${local.root_config.name_prefix}-${local.root_config.environment}-mixed-vpn"
  })
}

resource "aws_customer_gateway" "gcp" {
  count = local.mixed_network_enabled ? 1 : 0

  bgp_asn    = 65000
  ip_address = google_compute_address.mixed_vpn[0].address
  type       = "ipsec.1"
  tags = {
    Name = "${local.root_config.name_prefix}-${local.root_config.environment}-gcp"
  }
}

resource "aws_vpn_connection" "mixed" {
  count = local.mixed_network_enabled ? 1 : 0

  customer_gateway_id = aws_customer_gateway.gcp[0].id
  vpn_gateway_id      = aws_vpn_gateway.mixed[0].id
  type                = "ipsec.1"
  static_routes_only  = true

  tags = {
    Name = "${local.root_config.name_prefix}-${local.root_config.environment}-mixed"
  }
}

resource "aws_vpn_connection_route" "gcp" {
  for_each = local.aws_vpn_destinations

  destination_cidr_block = each.value
  vpn_connection_id      = aws_vpn_connection.mixed[0].id
}

resource "aws_route" "gcp" {
  for_each = local.mixed_network_enabled ? {
    for pair in setproduct(
      ["public", "workload"],
      keys(local.aws_vpn_destinations),
      ) : "${pair[0]}-${pair[1]}" => {
      route_table_id = module.aws.network.route_table_ids[pair[0]]
      destination    = local.aws_vpn_destinations[pair[1]]
    }
  } : {}

  route_table_id         = each.value.route_table_id
  destination_cidr_block = each.value.destination
  gateway_id             = aws_vpn_gateway.mixed[0].id
}

resource "aws_route_table" "mixed_database" {
  count = local.mixed_aws_database_enabled ? 1 : 0

  vpc_id = module.aws.network.vpc_id
  tags = {
    Name = "${local.root_config.name_prefix}-${local.root_config.environment}-database-private"
  }
}

resource "aws_route_table_association" "mixed_database" {
  for_each = local.mixed_aws_database_enabled ? {
    for index, subnet_id in module.aws.network.database_subnet_ids : tostring(index) => subnet_id
  } : {}

  subnet_id      = each.value
  route_table_id = aws_route_table.mixed_database[0].id
}

resource "aws_route" "mixed_database_to_gcp" {
  count = local.mixed_aws_database_enabled ? 1 : 0

  route_table_id         = aws_route_table.mixed_database[0].id
  destination_cidr_block = local.mixed_gcp_cidr
  gateway_id             = aws_vpn_gateway.mixed[0].id
}

resource "google_compute_vpn_tunnel" "aws" {
  count = local.mixed_network_enabled ? 1 : 0

  name                    = "${local.root_config.name_prefix}-${local.root_config.environment}-aws"
  region                  = module.gcp.network.region
  peer_ip                 = aws_vpn_connection.mixed[0].tunnel1_address
  shared_secret           = aws_vpn_connection.mixed[0].tunnel1_preshared_key
  target_vpn_gateway      = google_compute_vpn_gateway.mixed[0].id
  local_traffic_selector  = compact([local.mixed_gcp_cidr, local.mixed_gcp_database_cidr])
  remote_traffic_selector = [local.mixed_aws_cidr]

  depends_on = [
    google_compute_forwarding_rule.mixed_esp,
    google_compute_forwarding_rule.mixed_udp500,
    google_compute_forwarding_rule.mixed_udp4500,
  ]
}

resource "google_compute_route" "aws" {
  count = local.mixed_network_enabled ? 1 : 0

  name                = "${local.root_config.name_prefix}-${local.root_config.environment}-aws-private"
  network             = module.gcp.network.network_id
  dest_range          = local.mixed_aws_cidr
  priority            = 1000
  next_hop_vpn_tunnel = google_compute_vpn_tunnel.aws[0].id
}
