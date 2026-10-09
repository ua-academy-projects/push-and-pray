# One route per remote range, all pointing at the bastion. GCP routes apply
# to the whole VPC unless they name instance tags; these name the node tags,
# so the bastion itself keeps sending such packets into its tunnel instead of
# back to itself.
resource "google_compute_route" "via_bastion" {
  for_each = toset(var.destinations)

  name              = "${var.resource_prefix}-via-bastion-${replace(each.value, "/[./]/", "-")}"
  network           = var.network_id
  dest_range        = each.value
  next_hop_instance = var.bastion_self_link
  tags              = var.node_tags
}
