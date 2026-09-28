resource "azurerm_public_ip" "this" {
  for_each = {
    for name, vm in local.vms : name => vm if vm.assign_public_ip
  }

  name                = "${each.value.resource_name}-ip"
  location            = each.value.region
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = each.value.zone == null ? null : [each.value.zone]
  tags                = each.value.tags
}

resource "azurerm_network_interface" "this" {
  for_each = local.vms

  name                = "${each.value.resource_name}-nic"
  location            = each.value.region
  resource_group_name = var.resource_group_name
  tags                = each.value.tags

  ip_configuration {
    name                          = "primary"
    subnet_id                     = each.value.subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.internal_ip
    public_ip_address_id          = each.value.assign_public_ip ? azurerm_public_ip.this[each.key].id : null
  }
}

resource "azurerm_network_interface_security_group_association" "this" {
  for_each = local.vms

  network_interface_id      = azurerm_network_interface.this[each.key].id
  network_security_group_id = each.value.network_security_group_id
}

resource "azurerm_managed_disk" "data" {
  for_each = local.data_disks

  name                 = each.value.name
  location             = each.value.region
  resource_group_name  = var.resource_group_name
  storage_account_type = each.value.type
  create_option        = "Empty"
  disk_size_gb         = each.value.size_gb
  zone                 = each.value.zone
  tags                 = each.value.tags
}

resource "azurerm_linux_virtual_machine" "this" {
  for_each = local.vms

  name                            = each.value.resource_name
  computer_name                   = each.value.resource_name
  location                        = each.value.region
  resource_group_name             = var.resource_group_name
  zone                            = each.value.zone
  size                            = each.value.machine_type
  admin_username                  = each.value.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.this[each.key].id]
  custom_data                     = each.value.cloud_init == null ? null : base64encode(each.value.cloud_init)
  secure_boot_enabled             = true
  vtpm_enabled                    = true
  tags                            = each.value.tags

  admin_ssh_key {
    username   = each.value.admin_username
    public_key = each.value.ssh_public_key
  }

  os_disk {
    name                 = "${each.value.resource_name}-os"
    caching              = "ReadWrite"
    storage_account_type = each.value.boot_disk.type
    disk_size_gb         = each.value.boot_disk.size_gb
  }

  source_image_reference {
    publisher = each.value.image.publisher
    offer     = each.value.image.offer
    sku       = each.value.image.sku
    version   = each.value.image.version
  }

  dynamic "identity" {
    for_each = each.value.identity_id == null ? [] : [each.value.identity_id]

    content {
      type         = "UserAssigned"
      identity_ids = [identity.value]
    }
  }

  depends_on = [azurerm_network_interface_security_group_association.this]
}

resource "azurerm_virtual_machine_data_disk_attachment" "this" {
  for_each = local.data_disks

  managed_disk_id    = azurerm_managed_disk.data[each.key].id
  virtual_machine_id = azurerm_linux_virtual_machine.this[each.value.vm_name].id
  lun                = each.value.lun
  caching            = "ReadWrite"
}
