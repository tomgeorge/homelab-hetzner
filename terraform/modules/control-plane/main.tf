# Define IP addresses as locals for consistency
locals {
  # Control plane nodes start at .10
  control_plane_ips      = [for i in range(var.node_count) : cidrhost(var.subnet_cidr, 10 + i)]
  first_control_plane_ip = local.control_plane_ips[0]
}

# Control plane servers
resource "hcloud_server" "control_plane" {
  count = var.node_count

  name         = "${var.cluster_name}-control-plane-${count.index + 1}"
  server_type  = var.server_type
  image        = "ubuntu-22.04"
  location     = var.location
  ssh_keys     = [var.ssh_key_id]
  firewall_ids = var.firewall_ids

  labels = merge(
    var.tags,
    {
      role        = "control-plane"
      cluster     = var.cluster_name
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
    hostname     = "${var.cluster_name}-control-plane-${count.index + 1}"
    cluster_init = count.index == 0 ? "true" : "false"
    server_url   = count.index == 0 ? "" : "https://${local.first_control_plane_ip}:6443"
    k3s_token    = var.k3s_token
    k3s_version  = var.kubernetes_version
    private_ip   = local.control_plane_ips[count.index]
  })

  lifecycle {
    ignore_changes = [ssh_keys]
  }
}

# Attach servers to network
resource "hcloud_server_network" "control_plane" {
  count      = var.node_count
  server_id  = hcloud_server.control_plane[count.index].id
  network_id = var.network_id
  ip         = local.control_plane_ips[count.index]
}

# Wait for first control plane to be ready
resource "null_resource" "wait_for_control_plane" {
  depends_on = [hcloud_server_network.control_plane[0]]

  triggers = {
    server_id = hcloud_server.control_plane[0].id
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for control plane to be ready..."
      for i in {1..60}; do
        if ssh -i ${var.ssh_private_key_path} -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
           root@${hcloud_server.control_plane[0].ipv4_address} \
           "kubectl get nodes" 2>/dev/null; then
          echo "Control plane is ready!"
          break
        fi
        echo "Waiting... ($i/60)"
        sleep 10
      done
    EOT
  }
}

# Generate kubeconfig
data "external" "kubeconfig" {
  depends_on = [null_resource.wait_for_control_plane]

  program = ["bash", "-c", <<-EOT
    SSH_CMD="ssh -i ${var.ssh_private_key_path} -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@${hcloud_server.control_plane[0].ipv4_address}"

    # Get the kubeconfig from the first control plane node
    KUBECONFIG=$($SSH_CMD "sudo cat /etc/rancher/k3s/k3s.yaml" 2>/dev/null)

    if [ -z "$KUBECONFIG" ]; then
      echo '{"kubeconfig": ""}'
      exit 0
    fi

    # Replace localhost with actual IP
    KUBECONFIG=$(echo "$KUBECONFIG" | sed "s/127.0.0.1/${hcloud_server.control_plane[0].ipv4_address}/g")

    # Escape for JSON
    KUBECONFIG=$(echo "$KUBECONFIG" | jq -Rs .)

    echo "{\"kubeconfig\": $KUBECONFIG}"
  EOT
  ]
}

