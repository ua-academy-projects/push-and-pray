# The runtime identity of one VM. Separate from the VM itself: it outlives the
# instance, and the bindings that grant it access to secrets are written by a
# different part of the configuration.
resource "google_service_account" "workload" {
  account_id   = var.name
  display_name = var.name
  description  = coalesce(var.description, "Runtime identity for the ${var.name} workload VM")
}
