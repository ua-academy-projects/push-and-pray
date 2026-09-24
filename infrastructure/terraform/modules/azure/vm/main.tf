resource "azurerm_user_assigned_identity" "workload" {
  for_each = local.azure_vms

  name                = local.vm_names[each.key]
  resource_group_name = var.network.resource_group_name
  location            = var.network.location
  tags                = local.vm_tags[each.key]
}

resource "azurerm_public_ip" "public" {
  for_each = { for name, vm in local.azure_vms : name => vm if vm.assign_public_ip }

  name                = "${local.vm_names[each.key]}-ip"
  resource_group_name = var.network.resource_group_name
  location            = var.network.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = [local.zone]
  tags                = local.vm_tags[each.key]
}

resource "azurerm_network_interface" "workload" {
  for_each = local.azure_vms

  name                = "${local.vm_names[each.key]}-nic"
  resource_group_name = var.network.resource_group_name
  location            = var.network.location
  tags                = local.vm_tags[each.key]

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.network.vm_subnet_ids[each.key]
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.internal_ip
    public_ip_address_id          = each.value.assign_public_ip ? azurerm_public_ip.public[each.key].id : null
  }
}

resource "azurerm_network_interface_security_group_association" "workload" {
  for_each = local.azure_vms

  network_interface_id      = azurerm_network_interface.workload[each.key].id
  network_security_group_id = var.network.security_group_ids[each.value.role]
}

resource "azurerm_network_interface_application_security_group_association" "workload" {
  for_each = local.azure_vms

  depends_on = [azurerm_network_interface_security_group_association.workload]

  network_interface_id          = azurerm_network_interface.workload[each.key].id
  application_security_group_id = var.network.application_security_group_ids[each.value.role]
}

resource "azurerm_linux_virtual_machine" "workload" {
  for_each = local.azure_vms

  depends_on = [azurerm_network_interface_application_security_group_association.workload]

  name                = local.vm_names[each.key]
  computer_name       = local.vm_names[each.key]
  resource_group_name = var.network.resource_group_name
  location            = var.network.location
  size                = each.value.native_vm_type
  zone                = local.zone
  tags                = local.vm_tags[each.key]

  network_interface_ids = [azurerm_network_interface.workload[each.key].id]

  admin_username                  = local.admin_username
  disable_password_authentication = true

  admin_ssh_key {
    username   = local.admin_username
    public_key = var.config.ssh_users[local.admin_username]
  }

  custom_data = base64encode(local.cloud_init_user_data[each.key])

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.workload[each.key].id]
  }

  os_disk {
    caching              = "ReadWrite"
    disk_size_gb         = each.value.disk_size_gb
    storage_account_type = each.value.native_disk_type
  }

  source_image_reference {
    publisher = each.value.native_image.publisher
    offer     = each.value.native_image.offer
    sku       = each.value.native_image.sku
    version   = each.value.native_image.version
  }

  lifecycle {
    precondition {
      condition     = !each.value.assign_public_ip || contains(["ui", "bastion"], each.value.role)
      error_message = "Only workloads with role ui or bastion may receive a public IP."
    }
  }
}
