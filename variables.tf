variable "token" {
  description = "Paste in the packagecloud.io token that came with your license file."
  type = string
}

variable "location" {
  description = "The Azure location to deploy in"
  type = string
}

variable "linux_type" {
  description = "The variant of linux to be used. Latest AWS Marketplace AMI will be used. Can be overridden with ami input. Values are ubuntu-16.04, centos-7, centos-8, rhel-7, rhel-8, amazon-2"
  type = string
}

variable "instance_size" {
  description = "Instance size must have minimum of 16GB ram and 50GB disk"
  type = string
}

variable "public" {
  type = bool
  description = "Indicates if Public IP/DNS will be used to access Scalr"
}

variable "name_prefix" {
  description = "1-3 char prefix for instance names"
  type = string
}

variable "tags" {
  type = map
  description = "Add a map of tags (key = value) to be added to the deployed resources."
  default = null
}

variable server_count {
  type = number
  description = "Number of Scalr servers to run. Currently max = 1"
  default = 1
}
