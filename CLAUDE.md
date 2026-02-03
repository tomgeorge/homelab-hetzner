# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Rules

- Always run `terraform plan` before `terraform apply` and wait for user approval
- Use mise to manage CLI tools (helm, kubectl, terraform) - run `mise use <tool>` to add tools
- Run Helm and kubectl commands locally using `KUBECONFIG=./kubeconfig.yaml` instead of via SSH
- Use `helm_release` and `kubernetes_*` resources instead of `null_resource` with local-exec
- Pin Helm chart versions explicitly - never use "latest" or unpinned versions
- Use `set_sensitive` for secrets in helm_release to prevent logging

## Project Overview

Infrastructure-as-Code project that provisions a K3s Kubernetes cluster on Hetzner Cloud using Terraform with optional GitOps via ArgoCD.

## Commands

```bash
# Tool setup (uses mise.toml for versions)
mise install

# Terraform workflow
cd terraform
terraform init              # Download providers
terraform validate          # Check configuration
terraform fmt -recursive    # Format HCL files
terraform plan -out=tfplan  # Preview changes
terraform apply tfplan      # Deploy infrastructure
terraform destroy           # Tear down everything

# Cluster access (preferred: local kubectl/helm via mise)
export KUBECONFIG=$(pwd)/kubeconfig.yaml
kubectl get nodes
kubectl get pods -A
helm list -A

# Alternative: SSH to control plane
ssh -i ~/.ssh/id_homelab root@<control_plane_ip> "kubectl get nodes"

# ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

## Architecture

### Module Structure (`terraform/modules/`)
- **vpc/** - Hetzner private network (10.0.0.0/16) and subnet (10.0.1.0/24)
- **firewall/** - Security rules for SSH, K8s API, HTTP/S, NodePorts, and internal cluster traffic
- **control-plane/** - K3s server nodes (Ubuntu 22.04), cloud-init provisioning, kubeconfig retrieval
- **worker-nodes/** - K3s agent nodes that join cluster via token
- **load-balancer/** - Hetzner LB routing HTTP/S to workers, API to control plane in HA mode

### IP Allocation (subnet 10.0.1.0/24)
- Control plane: 10.0.1.10+
- Workers: 10.0.1.50+
- Load balancer: 10.0.1.100

### Deployment Order
VPC → Firewall → Control Plane → Workers → Load Balancer → HCCM/CSI → ArgoCD

### High Availability
Control plane count must be odd (1, 3, 5). With 3+ nodes, etcd quorum enables HA and LB gains API endpoint.

## Configuration

Copy `terraform.tfvars.example` to `terraform.tfvars` and set:
- `hcloud_token` (required) - Hetzner API token
- `cluster_name` - Resource name prefix (default: "homelab")
- `location` - fsn1 (cheapest), hel1, nbg1, ash
- `control_plane_count` - Must be odd
- `worker_node_count` - Minimum 1
- Optional toggles: `enable_firewall`, `enable_load_balancer`, `enable_persistent_volumes`, `install_argocd`
- Security: `allowed_ssh_ips`, `allowed_api_ips` for access restriction

## Tech Stack
- Terraform ≥ 1.0 with Hetzner, TLS, Random, Local, Null, Kubernetes, Helm providers
- K3s with Flannel CNI (VXLAN port 8472)
- Hetzner Cloud Controller Manager (Helm v1.19.0) and CSI Driver (Helm v2.6.0)
- ArgoCD for GitOps (Helm v5.55.0)
- Tailscale Operator for private network access (Helm v1.58.2)

## Debugging

```bash
# Node provisioning logs
ssh -i ssh_key.pem root@<ip>
tail -f /var/log/cloud-init-output.log
systemctl status k3s        # control plane
systemctl status k3s-agent  # workers
journalctl -u k3s -f        # K3s logs

# Terraform state inspection
terraform state list
terraform state show <resource>

# Check pod scheduling issues
kubectl describe pod <pod> -n kube-system | grep -A 20 Events
kubectl get nodes -o wide
kubectl describe node <node> | grep Taints
```

## Cluster Verification Steps

After `terraform apply`, verify the cluster is fully operational:

```bash
export KUBECONFIG=./kubeconfig.yaml

# 1. All Helm releases deployed
helm list -A

# 2. All nodes Ready (1 control plane + 3 workers)
kubectl get nodes

# 3. kube-system pods Running (coredns, hccm, csi, metrics-server)
kubectl get pods -n kube-system

# 4. ArgoCD pods Running
kubectl get pods -n argocd

# 5. Tailscale operator and proxy pods Running
kubectl get pods -n tailscale

# 6. No Pending pods (confirms HCCM removed node taints)
kubectl get pods -A | grep -i pending

# 7. ArgoCD service has Tailscale annotations
kubectl get svc argocd-server -n argocd -o jsonpath='{.metadata.annotations}'
```

## Known Issues & Solutions

### Hetzner Cloud-Init
- **Network interface**: Don't hardcode `ens10`. Auto-detect with: `ip -o addr show | grep "<private_ip>" | awk '{print $2}'`
- **Public IP for TLS SAN**: Fetch from metadata at boot: `curl -s http://169.254.169.254/hetzner/v1/metadata/public-ipv4`
- **Node labels**: Cannot set `node-role.kubernetes.io/*` via kubelet flags - use `kubectl label` after node joins

### HCCM (Hetzner Cloud Controller Manager)
- Installed via `helm_release` from `https://charts.hetzner.cloud`
- Requires `kubernetes_secret.hcloud` with both `token` and `network` keys
- Without the `network` key, HCCM fails with: `couldn't find key network in Secret kube-system/hcloud`
- Nodes have taint `node.cloudprovider.kubernetes.io/uninitialized: true` until HCCM initializes them - pods stay Pending
- CSI driver Helm chart creates its own storage class - don't create a duplicate

### Terraform Patterns

**Use declarative resources instead of null_resource:**
```hcl
# Good: helm_release resource
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "5.55.0"  # Always pin version
  namespace  = "argocd"

  set_sensitive {  # Protects secrets from logs
    name  = "configs.secret.key"
    value = var.secret_value
  }
}

# Bad: null_resource with shell commands
resource "null_resource" "install" {
  provisioner "local-exec" {
    command = "helm install ..."  # Avoid this pattern
  }
}
```

**Provider configuration** (`providers.tf`):
- Kubernetes and Helm providers connect via kubeconfig from control_plane module
- Uses `yamldecode()` and `base64decode()` to parse kubeconfig
- Providers depend on cluster being ready before resources are created

**When null_resource is still needed:**
- `wait_for_cluster` - SSH polling until nodes are Ready (kubeconfig doesn't exist yet)
- `wait_for_control_plane` - Initial K3s bootstrap check
- Cloud-init bootstrap operations

**Migration from kubectl-installed resources:**
- Helm cannot adopt resources not originally installed by Helm
- Must delete existing resources (namespace, CRDs, ClusterRoles) before Helm can install
- Use `terraform import` for resources that were already Helm-installed elsewhere
