output "firewall_id" {
  description = "ID of the created firewall"
  value       = hcloud_firewall.cluster.id
}

output "firewall_name" {
  description = "Name of the created firewall"
  value       = hcloud_firewall.cluster.name
}