# Look up the datacenter
data "vsphere_datacenter" "dc" {
    name = var.datacenter
}

# Look up the compute cluster
data "vsphere_compute_cluster" "cluster" {
    name          = var.cluster
    datacenter_id = data.vsphere_datacenter.dc.id
}

# Look up the datastore 
data "vsphere_datastore" "datastore" {
    name          = var.datastore
    datacenter_id = data.vsphere_datacenter.dc.id
}

# Look up the port group
data "vsphere_network" "network" {
    name          = var.network
    datacenter_id = data.vsphere_datacenter.dc.id
}

# Look up the VM template
data "vsphere_virtual_machine" "template" {
  name          = "ubuntu-22-04-template"
  datacenter_id = data.vsphere_datacenter.dc.id
}

# Look up the default resource pool for the cluster
data "vsphere_resource_pool" "pool" {
    name          = "$var{var.cluster}/Resources"
    datacenter_id = data.vsphere_datacenter.dc.id
}