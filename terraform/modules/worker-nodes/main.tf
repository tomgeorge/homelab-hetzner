# Define IP addresses as locals for consistency
locals {
  # Worker nodes start at .50
  worker_ips = [for i in range(var.node_count) : cidrhost(var.subnet_cidr, 50 + i)]
}

# Worker node servers
resource "hcloud_server" "worker" {
  count = var.node_count

  name        = "${var.cluster_name}-worker-${count.index + 1}"
  server_type = var.server_type
  image       = "ubuntu-22.04"
  location    = var.location
  ssh_keys    = [var.ssh_key_id]
  firewall_ids = var.firewall_ids

  labels = merge(
    var.tags,
    {
      role = "worker"
      cluster = var.cluster_name
      node_number = tostring(count.index + 1)
    }
  )

  # Network configuration
  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  # Cloud-init configuration
  user_data = templatefile("${path.module}/cloud-init.yaml", {
    hostname       = "${var.cluster_name}-worker-${count.index + 1}"
    server_ip      = var.control_plane_ip
    k3s_token      = var.k3s_token
    k3s_version    = var.kubernetes_version
    private_ip     = local.worker_ips[count.index]
  })

  lifecycle {
    ignore_changes = [ssh_keys]
  }
}

# Attach workers to network
resource "hcloud_server_network" "worker" {
  count      = var.node_count
  server_id  = hcloud_server.worker[count.index].id
  network_id = var.network_id
  ip         = local.worker_ips[count.index]
}