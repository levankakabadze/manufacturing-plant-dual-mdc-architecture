output "vm_name" {
  description = "Name of the deployed virtual machine"
  value       = vsphere_virtual_machine.vm.name
}

output "vm_ip_address" {
  description = "IP address of the deployed virtual machine"
  value       = vsphere_virtual_machine.vm.default_ip_address
}

output "vm_id" {
  description = "ID of the deployed virtual machine"
  value       = vsphere_virtual_machine.vm.id
}

output "vm_uuid" {
  description = "UUID of the deployed virtual machine"
  value       = vsphere_virtual_machine.vm.uuid
}
