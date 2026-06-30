locals {
  # Read the actual docker/ files from the package so the VM and the local
  # stack stay in sync (single source of truth).
  cloud_init = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    compose       = filebase64("${path.module}/../../docker/docker-compose.yml")
    prometheus    = filebase64("${path.module}/../../docker/config/prometheus.yml")
    datasource    = filebase64("${path.module}/../../docker/config/grafana/datasources/prometheus.yaml")
    dash_provider = filebase64("${path.module}/../../docker/config/grafana/dashboards/dashboards.yaml")
    dashboard     = filebase64("${path.module}/../../docker/config/grafana/dashboards/spark-databricks-overview.json")
  })
}

resource "azurerm_public_ip" "vm" {
  name                = "${var.prefix}-vm-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard" # provides VM outbound + inbound SSH
}

resource "azurerm_network_interface" "vm" {
  name                = "${var.prefix}-vm-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.vm.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.vm_private_ip
    public_ip_address_id          = azurerm_public_ip.vm.id
  }
}

resource "azurerm_linux_virtual_machine" "vm" {
  name                  = "${var.prefix}-mon-vm"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  size                  = var.vm_size
  admin_username        = "azureuser"
  network_interface_ids = [azurerm_network_interface.vm.id]
  custom_data           = base64encode(local.cloud_init)

  admin_ssh_key {
    username   = "azureuser"
    public_key = file(pathexpand(var.ssh_public_key_path))
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}
