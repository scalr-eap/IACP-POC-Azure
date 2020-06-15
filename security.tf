# Network Security Group and rules
resource "azurerm_network_security_group" "iacp_sg" {
    name                = "${var.name_prefix}-iacp-sg"
    location            = var.location
    resource_group_name = azurerm_resource_group.iacp_rg.name
    
    security_rule {
        name                       = "SSH"
        priority                   = 200
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_ranges    = [ "22" ]
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }

    security_rule {
        name                       = "HTTPS"
        priority                   = 100
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_ranges    = [ "443" ]
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }

    tags = var.tags
}
