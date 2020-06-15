# RG
resource "azurerm_resource_group" "iacp_rg" {
    name     = "${var.name_prefix}-iacp-rg"
    location = var.location

    tags = var.tags
}

# Network
resource "azurerm_virtual_network" "iacp_network" {
    name                = "${var.name_prefix}-iacp-network"
    address_space       = ["10.0.0.0/16"]
    location            = var.location
    resource_group_name = azurerm_resource_group.iacp_rg.name

    tags = var.tags
}

# Subnet
resource "azurerm_subnet" "iacp_subnet" {
    name                 = "${var.name_prefix}-iacp-subnet"
    resource_group_name  = azurerm_resource_group.iacp_rg.name
    virtual_network_name = azurerm_virtual_network.iacp_network.name
    address_prefix       = "10.0.1.0/24"
}

# Public IP
resource "azurerm_public_ip" "iacp_public_ip" {
    name                         = "${var.name_prefix}-iacp-ip"
    location                     = var.location
    resource_group_name          = azurerm_resource_group.iacp_rg.name
    allocation_method            = "Dynamic"
    domain_name_label            = "${var.name_prefix}iacp"

    tags = var.tags
}


# Create network interface
resource "azurerm_network_interface" "iacp_nic" {
    name                      = "${var.name_prefix}-iacp-nic"
    location                  = var.location
    resource_group_name       = azurerm_resource_group.iacp_rg.name
    internal_dns_name_label   = "${var.name_prefix}iacp"

    ip_configuration {
        name                          = "${var.name_prefix}-iacp-nic-cfg"
        subnet_id                     = azurerm_subnet.iacp_subnet.id
        private_ip_address_allocation = "Dynamic"
        public_ip_address_id          = azurerm_public_ip.iacp_public_ip.id
        primary                       = true
    }

    tags = var.tags
}

# Connect the security group to the network interface
resource "azurerm_network_interface_security_group_association" "example" {
    network_interface_id      = azurerm_network_interface.iacp_nic.id
    network_security_group_id = azurerm_network_security_group.iacp_sg.id
}
