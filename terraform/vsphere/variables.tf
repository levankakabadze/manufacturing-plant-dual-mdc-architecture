# vCenter Connection Variables
variable "vsphere_server" {
    description = "FQDN or IP address of the vSphere server"
    type        = string
}

variable "vsphere_user" {
    description = "vCenter service account username"
    type        = string
}

variable "vsphere_password" {
    description = "vCenter service account password"
    type        = string
    sensitive   = true
}

# Infrastructure Variables
variable "datacenter" {
    description = "vSphere datacenter name"
    type        = string
}

variable "cluster" {
    description = "vSphere cluster name"
    type        = string
}

variable "datastore" {
    description = "vSphere datastore name"
    type        = string
}

variable "network" {
    description = "PortGroup name for the VM network"
    type        = string
}

# Network customization variables
variable "vm_name" {
    description = "Name of the virtual machine"
    type        = string
}

variable "vm_ip_address" {
    description = "Static IP address for the virtual machine"
    type        = string
}

variable "vm_netmask" {
    description = "Netmask for the virtual machine"
    type        = number
    default     = 24
}

variable "vm_gateway" {
    description = "Gateway for the virtual machine"
    type        = string
}

variable "vm_dns_servers" {
    description = "DNS server for the virtual machine"
    type        = list(string)
}

variable "template" {
  description = "VM template name to clone from"
  type        = string
}

variable "vm_cpu" {
  description = "Number of vCPUs"
  type        = number
  default     = 4
}

variable "vm_memory" {
  description = "Memory in MB"
  type        = number
  default     = 8192
}

variable "vm_domain" {
  description = "Domain name for the VM"
  type        = string
  default     = "plant.local"
}

