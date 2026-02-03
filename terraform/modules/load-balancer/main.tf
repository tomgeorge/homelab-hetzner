# Define IP address for load balancer
locals {
  # Load balancer at .100
  load_balancer_ip = cidrhost(var.subnet_cidr, 100)
}

# Create Load Balancer
resource "hcloud_load_balancer" "cluster" {
  name               = "${var.cluster_name}-lb"
  load_balancer_type = var.load_balancer_type
  location           = var.location
  labels             = var.tags
}

# Attach Load Balancer to network
resource "hcloud_load_balancer_network" "cluster" {
  load_balancer_id = hcloud_load_balancer.cluster.id
  network_id        = var.network_id
  ip                = local.load_balancer_ip
}

# Create target for worker nodes (for ingress)
resource "hcloud_load_balancer_target" "workers" {
  count            = length(var.worker_node_ids)
  type             = "server"
  load_balancer_id = hcloud_load_balancer.cluster.id
  server_id        = var.worker_node_ids[count.index]
  use_private_ip   = true
}

# HTTP Service (port 80)
resource "hcloud_load_balancer_service" "http" {
  load_balancer_id = hcloud_load_balancer.cluster.id
  protocol         = "tcp"
  listen_port      = 80
  destination_port = 80

  health_check {
    protocol = "tcp"
    port     = 80
    interval = 15
    timeout  = 10
    retries  = 3
  }
}

# HTTPS Service (port 443)
resource "hcloud_load_balancer_service" "https" {
  load_balancer_id = hcloud_load_balancer.cluster.id
  protocol         = "tcp"
  listen_port      = 443
  destination_port = 443

  health_check {
    protocol = "tcp"
    port     = 443
    interval = 15
    timeout  = 10
    retries  = 3
  }
}

# Kubernetes API Service (port 6443) - for HA control plane
resource "hcloud_load_balancer_service" "kube_api" {
  count            = length(var.control_plane_ids) > 1 ? 1 : 0
  load_balancer_id = hcloud_load_balancer.cluster.id
  protocol         = "tcp"
  listen_port      = 6443
  destination_port = 6443

  health_check {
    protocol = "tcp"
    port     = 6443
    interval = 15
    timeout  = 10
    retries  = 3
  }
}

# Add control plane nodes as targets for API access (only for HA setup)
resource "hcloud_load_balancer_target" "control_plane" {
  count            = length(var.control_plane_ids) > 1 ? length(var.control_plane_ids) : 0
  type             = "server"
  load_balancer_id = hcloud_load_balancer.cluster.id
  server_id        = var.control_plane_ids[count.index]
  use_private_ip   = true
}