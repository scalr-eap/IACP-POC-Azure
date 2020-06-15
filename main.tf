#terraform {
#  backend "remote" {
#    hostname = "my.scalr.com"
#    organization = "org-sfgari365m7sck0"
#    workspaces {
#      name = "iacp-ha-install"
#    }
#  }
#}


locals {
    license_file         = "./license/license.json"

  # Currently forces server_count = 1. When multiple servers allowed will limit to the number of subnets
#  server_count         = min(length(data.aws_subnet_ids.scalr_ids),var.server_count,1)
}

locals {
  linux_types = [ 
    "ubuntu-16.04",
    "centos-7",
    "centos-8",
    "rhel-7",
    "rhel-8"
   ]
  offers = [ 
    "UbuntuServer", #CANONICAL
    "CentOS",
    "CentOS",
    "RHEL",
    "RHEL",
    ]
  skus = [ 
    "16.04.0-LTS",
    "7.7",
    "8_1",
    "7.7",
    "8.1"
   ]
  publishers = [ 
    "canonical", #CANONICAL
    "OpenLogic",
    "OpenLogic",
    "RedHat",
    "RedHat",
    ]
  users = [
    "ubuntu",
    "centos",
    "centos",
    "scalr",
    "scalr"
  ]
}

provider "azurerm" {
  version = "=2.0.0"
  features {}
}

###############################
#
# Scalr Server
#

resource "azurerm_linux_virtual_machine" "iacp_server" {
  name                  = "${var.name_prefix}-iacp-server"
  location              = var.location
  resource_group_name   = azurerm_resource_group.iacp_rg.name
  network_interface_ids = [azurerm_network_interface.iacp_nic.id]
  size                  = var.instance_size

  os_disk {
      name              = "${var.name_prefix}-iacp-osdisk"
      caching           = "ReadWrite"
      storage_account_type = "Premium_LRS"
  }

  source_image_reference {
      publisher = element(local.publishers,index(local.linux_types,var.linux_type))
      offer     = element(local.offers,index(local.linux_types,var.linux_type))
      sku       = element(local.skus,index(local.linux_types,var.linux_type))
      version   = "latest"
  }

  admin_username = element(local.users,index(local.linux_types,var.linux_type))
  disable_password_authentication = true
      
  admin_ssh_key {
      username       = element(local.users,index(local.linux_types,var.linux_type))
      public_key     = file("~/.ssh/id_rsa.pub")
  }

  tags = merge(
    map( "Name", "${var.name_prefix}-iacp-server"),
    var.tags )
  
  connection {
        host	= self.public_ip_address
        type     = "ssh"
        user     = element(local.users,index(local.linux_types,var.linux_type))
        private_key = file("~/.ssh/id_rsa")
        timeout  = "20m"
  }

  provisioner "file" {
        source = local.license_file
        destination = "/var/tmp/license.json"
  }

  provisioner "file" {
      source = "./SCRIPTS/scalr_install.sh"
      destination = "/var/tmp/scalr_install.sh"
  }

}

resource "azurerm_managed_disk" "iacp_disk" {
  name                 = "${var.name_prefix}-iacp-data-disk"
  location             = var.location
  resource_group_name  = azurerm_resource_group.iacp_rg.name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = "50"

  tags = {
    environment = "staging"
  }
}

resource "azurerm_virtual_machine_data_disk_attachment" "iacp_attach" {
  managed_disk_id    = azurerm_managed_disk.iacp_disk.id
  virtual_machine_id = azurerm_linux_virtual_machine.iacp_server.id
  lun                = "10"
  caching            = "ReadWrite"
}

## Certificate

resource "tls_private_key" "scalr_pk" {
  algorithm = "RSA"
}

locals {
  dns_name = var.public == true ? azurerm_public_ip.iacp_public_ip.fqdn : "${azurerm_linux_virtual_machine.iacp_server.name}.${azurerm_network_interface.iacp_nic.internal_dns_name_label}"
}

resource "tls_self_signed_cert" "scalr_cert" {
  key_algorithm   = "RSA"
  private_key_pem = tls_private_key.scalr_pk.private_key_pem

  subject {
    common_name  = local.dns_name
    organization = "Scalr"
  }

  validity_period_hours = 336

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "null_resource" "null_1" {
  depends_on = [azurerm_linux_virtual_machine.iacp_server,azurerm_virtual_machine_data_disk_attachment.iacp_attach]
  
  connection {
        host	= azurerm_linux_virtual_machine.iacp_server.public_ip_address
        type     = "ssh"
        user     = element(local.users,index(local.linux_types,var.linux_type))
        private_key = file("~/.ssh/id_rsa")
        timeout  = "20m"
  }

  provisioner "file" {
        content     = tls_self_signed_cert.scalr_cert.cert_pem
        destination = "/var/tmp/my.crt"
  }

  provisioner "file" {
        content     = tls_private_key.scalr_pk.private_key_pem
        destination = "/var/tmp/my.key"
  }
  provisioner "remote-exec" {
      inline = [
        "chmod +x /var/tmp/scalr_install.sh",
        "sudo /var/tmp/scalr_install.sh '${var.token}' ${local.dns_name}"
      ]
  }

}

resource "null_resource" "get_info" {

  depends_on = [null_resource.null_1 ]
    connection {
        host	= azurerm_linux_virtual_machine.iacp_server.public_ip_address
        type     = "ssh"
        user     = element(local.users,index(local.linux_types,var.linux_type))
        private_key = file("~/.ssh/id_rsa")
        timeout  = "20m"
  }

  provisioner "file" {
      source = "./SCRIPTS/get_pass.sh"
      destination = "/var/tmp/get_pass.sh"

  }
  provisioner "remote-exec" {
    inline = [
      "chmod +x /var/tmp/get_pass.sh",
      "sudo /var/tmp/get_pass.sh",
    ]
  }

}

output "dns_name" {
  value = "https://${local.dns_name}"
}

output "scalr_iacp_server_public_ip" {
  value = azurerm_linux_virtual_machine.iacp_server.public_ip_address
}


