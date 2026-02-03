output "server_ids" {
  description = "IDs of control plane servers"
  value       = hcloud_server.control_plane[*].id
}

output "control_plane_ip" {
  description = "Public IP of the first control plane node"
  value       = hcloud_server.control_plane[0].ipv4_address
}

output "public_ips" {
  description = "Public IPs of all control plane nodes"
  value       = hcloud_server.control_plane[*].ipv4_address
}

output "private_ips" {
  description = "Private IPs of all control plane nodes"
  value       = hcloud_server_network.control_plane[*].ip
}

output "control_plane_private_ip" {
  description = "Private IP of the first control plane node"
  value       = local.first_control_plane_ip
}

output "kubeconfig" {
  description = "Kubeconfig for accessing the cluster"
  value       = try(data.external.kubeconfig.result.kubeconfig, "")
  sensitive   = true
}