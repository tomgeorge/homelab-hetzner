output "load_balancer_id" {
  description = "ID of the load balancer"
  value       = hcloud_load_balancer.cluster.id
}

output "public_ip" {
  description = "Public IP address of the load balancer"
  value       = hcloud_load_balancer.cluster.ipv4
}

output "ipv6" {
  description = "IPv6 address of the load balancer"
  value       = hcloud_load_balancer.cluster.ipv6
}

output "dns_name" {
  description = "DNS name for the load balancer"
  value       = "${var.cluster_name}-lb.${var.location}.hetzner.cloud"
}