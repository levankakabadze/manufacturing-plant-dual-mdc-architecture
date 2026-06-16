# Site: Turkey Gebze (TR-GLK)
datacenter = "TR-GLK"
cluster    = "TRGLKCLS0002"
datastore  = "TRGLKESX0003_LUN_SSD"
network    = "vDS_GLK_VLAN_171"
template   = "ubuntu-22-04-template"

# VM Configuration
vm_name        = "TRGLKVM0001"
vm_cpu         = 4
vm_memory      = 8192
vm_ip_address  = "10.10.10.21"
vm_netmask     = 24
vm_gateway     = "10.10.10.1"
vm_dns_servers = ["10.10.10.15", "10.10.10.16"]
