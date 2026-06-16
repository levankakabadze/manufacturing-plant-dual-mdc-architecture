# vSphere Infrastructure Variables
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
  description = "Port group name for VM network"
  type        = string
}

variable "template" {
  description = "VM template name to clone from"
  type        = string
}

# VM Configuration Variables
variable "vm_name" {
  description = "Name of the virtual machine"
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

variable "vm_ip_address" {
  description = "Static IP address for the VM"
  type        = string
}

variable "vm_netmask" {
  description = "Subnet mask prefix length"
  type        = number
  default     = 24
}

variable "vm_gateway" {
  description = "Default gateway"
  type        = string
}

variable "vm_dns_servers" {
  description = "List of DNS servers"
  type        = list(string)
}

variable "vm_domain" {
  description = "Domain name for the VM"
  type        = string
  default     = "plant.local"
}
