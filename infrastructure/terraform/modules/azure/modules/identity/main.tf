# The runtime identity of one VM. Separate from the VM itself: it outlives the
# instance, and the role assignments that grant it access to secrets are
# written by a different part of the configuration. User-assigned rather than
# the VM's own system identity, which would die with the VM.
resource "azurerm_user_assigned_identity" "workload" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location

  tags = var.tags
}
