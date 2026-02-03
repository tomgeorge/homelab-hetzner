output "server_ids" {
  description = "IDs of worker node servers"
  value       = hcloud_server.worker[*].id
}

output "public_ips" {
  description = "Public IPs of worker nodes"
  value       = hcloud_server.worker[*].ipv4_address
}

output "private_ips" {
  description = "Private IPs of worker nodes"
  value       = hcloud_server_network.worker[*].ip
}