# Generate SSH Key if not provided
resource "tls_private_key" "ssh" {
  count     = var.ssh_public_key_path == "" ? 1 : 0
  algorithm = "ED25519"
}

# Generate K3s token for cluster join
resource "random_password" "k3s_token" {
  length  = 48
  special = false
}


# Create SSH Key in Hetzner
resource "hcloud_ssh_key" "cluster" {
  name       = "${var.cluster_name}-ssh"
  public_key = var.ssh_public_key_path != "" ? file(var.ssh_public_key_path) : tls_private_key.ssh[0].public_key_openssh
  labels     = var.tags
}

# VPC Module
module "vpc" {
  source = "./modules/vpc"

  cluster_name = var.cluster_name
  network_zone = var.network_zone
  network_cidr = var.network_cidr
  subnet_cidr  = var.subnet_cidr
  location     = var.location
  tags         = var.tags
}

# Firewall Module
module "firewall" {
  source = "./modules/firewall"
  count  = var.enable_firewall ? 1 : 0

  cluster_name    = var.cluster_name
  allowed_ssh_ips = var.allowed_ssh_ips
  allowed_api_ips = var.allowed_api_ips
  tags            = var.tags
}

# Control Plane Module
module "control_plane" {
  source = "./modules/control-plane"

  cluster_name         = var.cluster_name
  node_count           = var.control_plane_count
  server_type          = var.control_plane_type
  location             = var.location
  network_id           = module.vpc.network_id
  subnet_id            = module.vpc.subnet_id
  subnet_cidr          = var.subnet_cidr
  ssh_key_id           = hcloud_ssh_key.cluster.id
  ssh_private_key_path = var.ssh_public_key_path != "" ? var.ssh_private_key_path : "${path.module}/ssh_key.pem"
  k3s_token            = random_password.k3s_token.result
  kubernetes_version   = var.kubernetes_version
  firewall_ids         = var.enable_firewall ? [module.firewall[0].firewall_id] : []
  tags                 = var.tags

  depends_on = [local_sensitive_file.ssh_private_key]
}

# Worker Nodes Module
module "worker_nodes" {
  source = "./modules/worker-nodes"

  cluster_name       = var.cluster_name
  node_count         = var.worker_node_count
  server_type        = var.worker_node_type
  location           = var.location
  network_id         = module.vpc.network_id
  subnet_id          = module.vpc.subnet_id
  subnet_cidr        = var.subnet_cidr
  ssh_key_id         = hcloud_ssh_key.cluster.id
  k3s_token          = random_password.k3s_token.result
  control_plane_ip   = module.control_plane.control_plane_private_ip
  kubernetes_version = var.kubernetes_version
  firewall_ids       = var.enable_firewall ? [module.firewall[0].firewall_id] : []
  tags               = var.tags

  depends_on = [module.control_plane]
}

# Load Balancer Module
module "load_balancer" {
  source = "./modules/load-balancer"
  count  = var.enable_load_balancer ? 1 : 0

  cluster_name       = var.cluster_name
  load_balancer_type = var.load_balancer_type
  location           = var.location
  network_id         = module.vpc.network_id
  subnet_cidr        = var.subnet_cidr
  control_plane_ids  = module.control_plane.server_ids
  worker_node_ids    = module.worker_nodes.server_ids
  tags               = var.tags
}

# Save kubeconfig locally
resource "local_sensitive_file" "kubeconfig" {
  content  = module.control_plane.kubeconfig
  filename = "${path.module}/kubeconfig.yaml"

  file_permission = "0600"
}

# Save SSH private key if generated
resource "local_sensitive_file" "ssh_private_key" {
  count    = var.ssh_public_key_path == "" ? 1 : 0
  content  = tls_private_key.ssh[0].private_key_pem
  filename = "${path.module}/ssh_key.pem"

  file_permission = "0600"
}

# Bootstrap cluster components
resource "null_resource" "wait_for_cluster" {
  depends_on = [
    module.control_plane,
    module.worker_nodes,
    local_sensitive_file.kubeconfig
  ]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for cluster to be ready..."
      sleep 30
      SSH_CMD="ssh -i ${var.ssh_public_key_path != "" ? var.ssh_private_key_path : "${path.module}/ssh_key.pem"} -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@${module.control_plane.control_plane_ip}"

      # Wait for nodes to be ready
      for i in {1..60}; do
        if $SSH_CMD "kubectl get nodes" 2>/dev/null | grep -q Ready; then
          echo "Cluster nodes are ready!"
          break
        fi
        echo "Waiting for nodes... ($i/60)"
        sleep 5
      done

      # Show cluster status
      $SSH_CMD "kubectl get nodes"
    EOT
  }
}

# Create Hetzner Cloud secret for HCCM and CSI (using kubernetes provider)
resource "kubernetes_secret" "hcloud" {
  metadata {
    name      = "hcloud"
    namespace = "kube-system"
  }

  data = {
    token   = var.hcloud_token
    network = tostring(module.vpc.network_id)
  }

  depends_on = [null_resource.wait_for_cluster]
}

# Install Hetzner Cloud Controller Manager (using helm provider)
resource "helm_release" "hccm" {
  count = var.enable_load_balancer || var.enable_persistent_volumes ? 1 : 0

  name       = "hcloud-cloud-controller-manager"
  repository = "https://charts.hetzner.cloud"
  chart      = "hcloud-cloud-controller-manager"
  version    = "1.19.0"
  namespace  = "kube-system"

  set {
    name  = "networking.enabled"
    value = "true"
  }

  set {
    name  = "networking.clusterCIDR"
    value = "10.42.0.0/16"
  }

  depends_on = [kubernetes_secret.hcloud]
}

# Install Hetzner CSI Driver (using helm provider)
resource "helm_release" "hcloud_csi" {
  count = var.enable_persistent_volumes ? 1 : 0

  name       = "hcloud-csi"
  repository = "https://charts.hetzner.cloud"
  chart      = "hcloud-csi"
  version    = "2.6.0"
  namespace  = "kube-system"

  depends_on = [kubernetes_secret.hcloud]
}

# Create default storage class
resource "kubernetes_storage_class" "hcloud_volumes" {
  count = var.enable_persistent_volumes ? 1 : 0

  metadata {
    name = "hcloud-volumes"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "csi.hetzner.cloud"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  depends_on = [helm_release.hcloud_csi]
}

# Install ArgoCD (using helm provider with Tailscale annotations)
resource "helm_release" "argocd" {
  count = var.install_argocd ? 1 : 0

  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "5.55.0"
  namespace        = var.argocd_namespace
  create_namespace = true

  # Server service type - ClusterIP for Tailscale, LoadBalancer otherwise
  set {
    name  = "server.service.type"
    value = var.install_tailscale ? "ClusterIP" : "LoadBalancer"
  }

  # Tailscale annotations (when enabled)
  dynamic "set" {
    for_each = var.install_tailscale ? [1] : []
    content {
      name  = "server.service.annotations.tailscale\\.com/expose"
      value = "true"
    }
  }

  dynamic "set" {
    for_each = var.install_tailscale ? [1] : []
    content {
      name  = "server.service.annotations.tailscale\\.com/hostname"
      value = "argocd"
    }
  }

  depends_on = [
    null_resource.wait_for_cluster,
    helm_release.hccm,
    helm_release.hcloud_csi
  ]
}

# Install Tailscale Operator (using helm provider)
resource "helm_release" "tailscale_operator" {
  count = var.install_tailscale ? 1 : 0

  name             = "tailscale-operator"
  repository       = "https://pkgs.tailscale.com/helmcharts"
  chart            = "tailscale-operator"
  version          = "1.58.2"
  namespace        = "tailscale"
  create_namespace = true

  set_sensitive {
    name  = "oauth.clientId"
    value = var.tailscale_oauth_client_id
  }

  set_sensitive {
    name  = "oauth.clientSecret"
    value = var.tailscale_oauth_client_secret
  }

  depends_on = [null_resource.wait_for_cluster]
}

