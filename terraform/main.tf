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

# Create Hetzner Cloud secret for HCCM and CSI
resource "null_resource" "create_hcloud_secret" {
  depends_on = [null_resource.wait_for_cluster]

  provisioner "local-exec" {
    command = <<-EOT
      SSH_CMD="ssh -i ${var.ssh_public_key_path != "" ? var.ssh_private_key_path : "${path.module}/ssh_key.pem"} -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@${module.control_plane.control_plane_ip}"

      # Create secret for Hetzner Cloud token and network (used by both HCCM and CSI)
      $SSH_CMD "kubectl -n kube-system create secret generic hcloud \
        --from-literal=token='${var.hcloud_token}' \
        --from-literal=network='${module.vpc.network_id}' \
        --dry-run=client -o yaml | kubectl apply -f -"

      echo "Hetzner Cloud secret created successfully"
    EOT
  }
}

# Install Hetzner Cloud Controller Manager
resource "null_resource" "install_hccm" {
  count = var.enable_load_balancer || var.enable_persistent_volumes ? 1 : 0

  depends_on = [null_resource.create_hcloud_secret]

  provisioner "local-exec" {
    command = <<-EOT
      SSH_CMD="ssh -i ${var.ssh_public_key_path != "" ? var.ssh_private_key_path : "${path.module}/ssh_key.pem"} -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@${module.control_plane.control_plane_ip}"

      # Apply HCCM with network support
      $SSH_CMD "kubectl apply -f https://github.com/hetznercloud/hcloud-cloud-controller-manager/releases/latest/download/ccm-networks.yaml"

      echo "Hetzner Cloud Controller Manager installed successfully"
    EOT
  }
}

# Install Hetzner CSI Driver
resource "null_resource" "install_csi" {
  count = var.enable_persistent_volumes ? 1 : 0

  depends_on = [null_resource.create_hcloud_secret]

  provisioner "local-exec" {
    command = <<-EOT
      SSH_CMD="ssh -i ${var.ssh_public_key_path != "" ? var.ssh_private_key_path : "${path.module}/ssh_key.pem"} -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@${module.control_plane.control_plane_ip}"

      # Install CSI driver
      $SSH_CMD "kubectl apply -f https://raw.githubusercontent.com/hetznercloud/csi-driver/main/deploy/kubernetes/hcloud-csi.yaml"

      # Wait for CSI driver to be ready
      sleep 10

      # Create default storage class
      $SSH_CMD 'cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: hcloud-volumes
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: csi.hetzner.cloud
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
parameters:
  csiDriver: csi.hetzner.cloud
EOF'

      echo "Hetzner CSI Driver and default storage class installed successfully"
    EOT
  }
}

# Install ArgoCD
resource "null_resource" "install_argocd" {
  count = var.install_argocd ? 1 : 0

  depends_on = [
    null_resource.wait_for_cluster,
    null_resource.install_hccm,
    null_resource.install_csi
  ]

  provisioner "local-exec" {
    command = <<-EOT
      SSH_CMD="ssh -i ${var.ssh_public_key_path != "" ? var.ssh_private_key_path : "${path.module}/ssh_key.pem"} -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@${module.control_plane.control_plane_ip}"

      echo "Installing ArgoCD in namespace ${var.argocd_namespace}..."

      # Create namespace and install ArgoCD
      $SSH_CMD "kubectl create namespace ${var.argocd_namespace} --dry-run=client -o yaml | kubectl apply -f -"
      $SSH_CMD "kubectl apply -n ${var.argocd_namespace} -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"

      # Wait for ArgoCD to be ready
      echo "Waiting for ArgoCD pods to be ready..."
      $SSH_CMD "kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n ${var.argocd_namespace} --timeout=300s"

      # Patch ArgoCD server to use LoadBalancer
      $SSH_CMD "kubectl patch svc argocd-server -n ${var.argocd_namespace} -p '{\"spec\": {\"type\": \"LoadBalancer\"}}'"

      echo "ArgoCD installation complete!"
    EOT
  }
}

# Install Tailscale Operator (runs locally using generated kubeconfig)
resource "null_resource" "install_tailscale" {
  count = var.install_tailscale ? 1 : 0

  depends_on = [null_resource.wait_for_cluster, local_sensitive_file.kubeconfig]

  provisioner "local-exec" {
    command = <<-EOT
      export KUBECONFIG="${path.module}/kubeconfig.yaml"

      echo "Installing Tailscale operator..."

      # Add Tailscale Helm repo
      helm repo add tailscale https://pkgs.tailscale.com/helmcharts 2>/dev/null || true
      helm repo update

      # Install Tailscale operator
      helm upgrade --install tailscale-operator tailscale/tailscale-operator \
        --namespace=tailscale --create-namespace \
        --set-string oauth.clientId='${var.tailscale_oauth_client_id}' \
        --set-string oauth.clientSecret='${var.tailscale_oauth_client_secret}' \
        --wait

      echo "Tailscale operator installed successfully"
    EOT
  }
}

# Expose ArgoCD via Tailscale (runs locally using generated kubeconfig)
resource "null_resource" "expose_argocd_tailscale" {
  count = var.install_tailscale && var.install_argocd ? 1 : 0

  depends_on = [
    null_resource.install_tailscale,
    null_resource.install_argocd
  ]

  provisioner "local-exec" {
    command = <<-EOT
      export KUBECONFIG="${path.module}/kubeconfig.yaml"

      # Annotate ArgoCD service to expose via Tailscale
      kubectl annotate svc argocd-server -n argocd \
        tailscale.com/expose='true' \
        tailscale.com/hostname='argocd' \
        --overwrite

      echo "ArgoCD exposed to tailnet as 'argocd'"
    EOT
  }
}

