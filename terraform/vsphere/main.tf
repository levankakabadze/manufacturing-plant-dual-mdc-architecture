terraform {
  required_providers {
    vsphere = {
      source  = "vmware/vsphere"
      version = "~> 2.6"
    }
  }
  required_version = ">= 1.5.0"
}

provider "vsphere" {
  user                 = var.vsphere_user
  password             = var.vsphere_password
  vsphere_server       = var.vsphere_server
  allow_unverified_ssl = true
}

module "plant_vm" {
  source = "../modules/plant-vm"

  # vSphere Infrastructure
  datacenter = var.datacenter
  cluster    = var.cluster
  datastore  = var.datastore
  network    = var.network
  template   = var.template

  # VM Configuration
  vm_name        = var.vm_name
  vm_cpu         = var.vm_cpu
  vm_memory      = var.vm_memory
  vm_ip_address  = var.vm_ip_address
  vm_netmask     = var.vm_netmask
  vm_gateway     = var.vm_gateway
  vm_dns_servers = var.vm_dns_servers
  vm_domain      = var.vm_domain
}
