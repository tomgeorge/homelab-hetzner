resource "hcloud_firewall" "cluster" {
  name   = "${var.cluster_name}-firewall"
  labels = var.tags

  # Allow SSH access
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "22"
    source_ips  = length(var.allowed_ssh_ips) > 0 ? var.allowed_ssh_ips : ["0.0.0.0/0", "::/0"]
    description = "Allow SSH"
  }

  # Allow Kubernetes API access
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "6443"
    source_ips  = length(var.allowed_api_ips) > 0 ? var.allowed_api_ips : ["0.0.0.0/0", "::/0"]
    description = "Allow Kubernetes API"
  }

  # Allow HTTP traffic
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "80"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "Allow HTTP"
  }

  # Allow HTTPS traffic
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "443"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "Allow HTTPS"
  }

  # Allow NodePort range (default K3s/K8s range)
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "30000-32767"
    source_ips  = ["0.0.0.0/0", "::/0"]
    description = "Allow NodePort Services"
  }

  # Allow internal cluster communication (flannel VXLAN)
  rule {
    direction   = "in"
    protocol    = "udp"
    port        = "8472"
    source_ips  = ["10.0.0.0/16"]
    description = "Allow Flannel VXLAN"
  }

  # Allow internal cluster communication (kubelet)
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "10250"
    source_ips  = ["10.0.0.0/16"]
    description = "Allow Kubelet API"
  }

  # Allow metrics server
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "10251-10252"
    source_ips  = ["10.0.0.0/16"]
    description = "Allow kube-scheduler and kube-controller metrics"
  }

  # Allow etcd communication for HA setups
  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "2379-2380"
    source_ips  = ["10.0.0.0/16"]
    description = "Allow etcd"
  }

  # Allow all outbound traffic
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "any"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "Allow all outbound TCP"
  }

  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "any"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "Allow all outbound UDP"
  }

  rule {
    direction       = "out"
    protocol        = "icmp"
    destination_ips = ["0.0.0.0/0", "::/0"]
    description     = "Allow all outbound ICMP"
  }
}