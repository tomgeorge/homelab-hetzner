output "cluster_name" {
  description = "Name of the Kubernetes cluster"
  value       = var.cluster_name
}

output "control_plane_ip" {
  description = "Public IP of the control plane (first node)"
  value       = module.control_plane.control_plane_ip
}

output "control_plane_private_ips" {
  description = "Private IPs of all control plane nodes"
  value       = module.control_plane.private_ips
  sensitive   = false
}

output "worker_node_ips" {
  description = "Public IPs of worker nodes"
  value       = module.worker_nodes.public_ips
}

output "worker_node_private_ips" {
  description = "Private IPs of worker nodes"
  value       = module.worker_nodes.private_ips
  sensitive   = false
}

output "load_balancer_ip" {
  description = "Public IP of the load balancer"
  value       = var.enable_load_balancer ? module.load_balancer[0].public_ip : "N/A"
}

output "kubeconfig_path" {
  description = "Path to the generated kubeconfig file"
  value       = "${path.module}/kubeconfig.yaml"
}

output "ssh_private_key_path" {
  description = "Path to SSH private key"
  value       = var.ssh_public_key_path == "" ? "${path.module}/ssh_key.pem" : var.ssh_private_key_path
}

output "ssh_command" {
  description = "SSH command to connect to the control plane"
  value       = "ssh -i ${var.ssh_public_key_path == "" ? "${path.module}/ssh_key.pem" : var.ssh_private_key_path} root@${module.control_plane.control_plane_ip}"
}

output "kubectl_command" {
  description = "Command to use kubectl with the generated kubeconfig"
  value       = "export KUBECONFIG=${path.module}/kubeconfig.yaml"
}

output "argocd_info" {
  description = "ArgoCD access information"
  value = var.install_argocd ? {
    namespace    = var.argocd_namespace
    url          = "https://${var.enable_load_balancer ? module.load_balancer[0].public_ip : module.control_plane.control_plane_ip}"
    get_password = "kubectl -n ${var.argocd_namespace} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
  } : null
}

output "tailscale_info" {
  description = "Tailscale access information"
  value = var.install_tailscale ? {
    argocd_tailscale_url = "https://argocd.<tailnet-name>.ts.net"
    note                 = "Replace <tailnet-name> with your actual tailnet name from the Tailscale admin console"
  } : null
}

output "estimated_monthly_cost" {
  description = "Estimated monthly cost in USD"
  value       = <<-EOT
    Control Plane (${var.control_plane_count}x ${var.control_plane_type}): $${format("%.2f", var.control_plane_count * (
      var.control_plane_type == "cpx11" ? 4.04 :
      var.control_plane_type == "cpx21" ? 7.40 :
      var.control_plane_type == "cpx31" ? 13.00 :
      var.control_plane_type == "cpx41" ? 24.25 : 0
    ))}
    Worker Nodes (${var.worker_node_count}x ${var.worker_node_type}): $${format("%.2f", var.worker_node_count * (
      var.worker_node_type == "cpx11" ? 4.04 :
      var.worker_node_type == "cpx21" ? 7.40 :
      var.worker_node_type == "cpx31" ? 13.00 :
      var.worker_node_type == "cpx41" ? 24.25 : 0
    ))}
    Load Balancer: $${var.enable_load_balancer ? "6.12" : "0.00"}
    Total: ~$${format("%.2f",
      var.control_plane_count * (
        var.control_plane_type == "cpx11" ? 4.04 :
        var.control_plane_type == "cpx21" ? 7.40 :
        var.control_plane_type == "cpx31" ? 13.00 :
        var.control_plane_type == "cpx41" ? 24.25 : 0
      ) +
      var.worker_node_count * (
        var.worker_node_type == "cpx11" ? 4.04 :
        var.worker_node_type == "cpx21" ? 7.40 :
        var.worker_node_type == "cpx31" ? 13.00 :
        var.worker_node_type == "cpx41" ? 24.25 : 0
      ) +
      (var.enable_load_balancer ? 6.12 : 0)
    )}/month
  EOT
}