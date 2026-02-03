output "network_id" {
  description = "ID of the created network"
  value       = hcloud_network.cluster.id
}

output "subnet_id" {
  description = "ID of the created subnet"
  value       = hcloud_network_subnet.cluster.id
}

output "network_cidr" {
  description = "CIDR of the network"
  value       = var.network_cidr
}

output "subnet_cidr" {
  description = "CIDR of the subnet"
  value       = var.subnet_cidr
}