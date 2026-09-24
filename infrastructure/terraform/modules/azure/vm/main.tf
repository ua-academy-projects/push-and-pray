resource "azurerm_public_ip" "vm" {
  for_each = { for name, vm in local.vms : name => vm if vm.assign_public_ip }

  name                = "${local.resource_prefix}-${each.key}-ip"
  location            = var.config.locations[each.value.location].azure.region
  resource_group_name = var.resource_group_names[each.value.location]
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.labels_by_vm[each.key]
}

resource "azurerm_network_interface" "vm" {
  for_each = local.vms

  name                = "${local.resource_prefix}-${each.key}-nic"
  location            = var.config.locations[each.value.location].azure.region
  resource_group_name = var.resource_group_names[each.value.location]
  tags                = local.labels_by_vm[each.key]

  ip_configuration {
    name                          = "primary"
    subnet_id                     = (each.value.role == "bastion" || each.value.assign_public_ip) ? var.management_subnet_ids[each.value.location] : var.workload_subnet_ids[each.value.location]
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.internal_ip
    public_ip_address_id          = try(azurerm_public_ip.vm[each.key].id, null)
  }
}

resource "azurerm_network_interface_security_group_association" "vm" {
  for_each = local.vms

  network_interface_id      = azurerm_network_interface.vm[each.key].id
  network_security_group_id = var.network_security_group_ids[each.key]
}

resource "azurerm_linux_virtual_machine" "workload" {
  for_each = local.vms

  name                            = "${local.resource_prefix}-${each.key}"
  location                        = var.config.locations[each.value.location].azure.region
  resource_group_name             = var.resource_group_names[each.value.location]
  size                            = var.config.provider_mappings.instance_types[each.value.size].azure.vm_size
  admin_username                  = local.ssh_user
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.vm[each.key].id]
  custom_data                     = local.bootstrap_scripts[each.key]
  tags                            = local.labels_by_vm[each.key]

  identity {
    type = "SystemAssigned"
  }

  admin_ssh_key {
    username   = local.ssh_user
    public_key = trimspace(var.config.ssh_users[local.ssh_user])
  }

  source_image_reference {
    publisher = var.config.provider_mappings.images[each.value.image].azure.publisher
    offer     = var.config.provider_mappings.images[each.value.image].azure.offer
    sku       = var.config.provider_mappings.images[each.value.image].azure.sku
    version   = var.config.provider_mappings.images[each.value.image].azure.version
  }

  os_disk {
    name                 = "${local.resource_prefix}-${each.key}-os"
    caching              = "ReadWrite"
    storage_account_type = var.config.provider_mappings.disk_types[each.value.disk_type].azure
    disk_size_gb = max(each.value.disk_size, var.config.provider_mappings.images[each.value.image].azure.min_disk_size_gb)
  }

  lifecycle {
    precondition {
      condition     = !each.value.assign_public_ip || contains(["ui", "bastion"], each.value.role)
      error_message = "Only workloads with role ui or bastion may receive a public IP."
    }
  }

  depends_on = [azurerm_network_interface_security_group_association.vm]
}

resource "azurerm_managed_disk" "data" {
  for_each = local.data_disks

  name                 = "${local.resource_prefix}-${each.key}"
  location             = var.config.locations[each.value.location].azure.region
  resource_group_name  = var.resource_group_names[each.value.location]
  storage_account_type = var.config.provider_mappings.disk_types[each.value.disk_type].azure
  create_option        = "Empty"
  disk_size_gb         = each.value.disk_size
  tags                 = local.labels_by_vm[each.value.vm_name]
}

resource "azurerm_virtual_machine_data_disk_attachment" "data" {
  for_each = local.data_disks

  managed_disk_id    = azurerm_managed_disk.data[each.key].id
  virtual_machine_id = azurerm_linux_virtual_machine.workload[each.value.vm_name].id
  lun                = each.value.lun
  caching            = "None"
}
