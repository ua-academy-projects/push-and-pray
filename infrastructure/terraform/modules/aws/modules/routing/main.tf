# Every route table gets every remote range, pointing at the bastion's network
# interface: nodes with a public address sit in the public subnet, the rest in
# the private one, and both have to reach the other clouds and the tailnet.
resource "aws_route" "via_bastion" {
  for_each = {
    for pair in setproduct(keys(var.route_table_ids), var.destinations) :
    "${pair[0]}/${pair[1]}" => {
      route_table_id = var.route_table_ids[pair[0]]
      destination    = pair[1]
    }
  }

  route_table_id         = each.value.route_table_id
  destination_cidr_block = each.value.destination
  network_interface_id   = var.bastion_network_interface_id
}
