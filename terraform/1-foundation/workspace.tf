# VNet-injected workspace with Secure Cluster Connectivity (no public IP).
# Clusters launch into your two delegated subnets, so the monitoring VM in the
# same VNet is reachable over its private IP – no peering required.
resource "azurerm_databricks_workspace" "this" {
  name                        = "${var.prefix}-dbx"
  resource_group_name         = azurerm_resource_group.rg.name
  location                    = azurerm_resource_group.rg.location
  sku                         = "premium"
  managed_resource_group_name = "${var.prefix}-dbx-managed-rg"

  custom_parameters {
    no_public_ip                                        = true
    virtual_network_id                                  = azurerm_virtual_network.vnet.id
    public_subnet_name                                  = azurerm_subnet.dbx_host.name
    private_subnet_name                                 = azurerm_subnet.dbx_container.name
    public_subnet_network_security_group_association_id  = azurerm_subnet_network_security_group_association.dbx_host.id
    private_subnet_network_security_group_association_id = azurerm_subnet_network_security_group_association.dbx_container.id
  }

  depends_on = [
    azurerm_subnet_network_security_group_association.dbx_host,
    azurerm_subnet_network_security_group_association.dbx_container,
    azurerm_subnet_nat_gateway_association.dbx_host,
    azurerm_subnet_nat_gateway_association.dbx_container,
  ]
}
