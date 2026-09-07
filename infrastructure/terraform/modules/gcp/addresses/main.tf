resource "google_compute_address" "public" {
  for_each = local.public_vms

  name   = "${local.resource_prefix}-${each.key}-ip"
  labels = merge(local.merged_common_labels, try(each.value.labels, {}), { role = each.value.role })
}
