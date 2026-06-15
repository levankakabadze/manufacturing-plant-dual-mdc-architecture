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