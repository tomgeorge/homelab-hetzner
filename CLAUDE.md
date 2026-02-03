# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Rules

- Always run `terraform plan` before `terraform apply` and wait for user approval
- Use mise to manage CLI tools (helm, kubectl, terraform) - run `mise use <tool>` to add tools
- Run Helm and kubectl commands locally using `KUBECONFIG=./kubeconfig.yaml` instead of via SSH
- Terraform provisioners for Helm/kubectl should use local execution with the generated kubeconfig, not SSH

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
ssh -i ~/.ssh/id_homelab root@<control_plane_ip> "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
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
- Terraform ≥ 1.0 with Hetzner, TLS, Random, Local, Null providers
- K3s with Flannel CNI (VXLAN port 8472)
- Hetzner Cloud Controller Manager and CSI Driver
- ArgoCD for GitOps (apps go in `argocd/apps/`)

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
SSH_CMD="ssh -i ~/.ssh/id_homelab -o StrictHostKeyChecking=no root@<control_plane_ip>"

# 1. All nodes Ready (1 control plane + 3 workers)
$SSH_CMD "kubectl get nodes"

# 2. kube-system pods Running (coredns, hccm, local-path-provisioner, metrics-server)
$SSH_CMD "kubectl get pods -n kube-system"

# 3. ArgoCD pods Running
$SSH_CMD "kubectl get pods -n argocd"

# 4. No Pending pods (confirms HCCM removed node taints)
$SSH_CMD "kubectl get pods -A | grep -i pending"

# 5. hcloud secret has both token and network keys
$SSH_CMD "kubectl get secret hcloud -n kube-system -o jsonpath='{.data}'"

# 6. TLS cert includes public IP (kubeconfig works remotely)
$SSH_CMD "openssl s_client -connect <control_plane_ip>:6443 2>/dev/null </dev/null | openssl x509 -noout -text | grep -A1 'Subject Alternative Name'"
```

## Known Issues & Solutions

### Hetzner Cloud-Init
- **Network interface**: Don't hardcode `ens10`. Auto-detect with: `ip -o addr show | grep "<private_ip>" | awk '{print $2}'`
- **Public IP for TLS SAN**: Fetch from metadata at boot: `curl -s http://169.254.169.254/hetzner/v1/metadata/public-ipv4`
- **Node labels**: Cannot set `node-role.kubernetes.io/*` via kubelet flags - use `kubectl label` after node joins

### HCCM (Hetzner Cloud Controller Manager)
- The `ccm-networks.yaml` manifest requires the hcloud secret to have BOTH `token` AND `network` keys
- Without the `network` key, HCCM fails with: `couldn't find key network in Secret kube-system/hcloud`
- Nodes have taint `node.cloudprovider.kubernetes.io/uninitialized: true` until HCCM initializes them - pods stay Pending

### Terraform Provisioners
- Helm/kubectl provisioners should run locally with `KUBECONFIG="${path.module}/kubeconfig.yaml"` (not via SSH)
- Cloud-init and K3s bootstrap provisioners use SSH since kubeconfig doesn't exist yet
- `null_resource` needs `triggers` block to re-run when dependencies change (e.g., server ID)
- Tilde (`~`) in paths may not expand in local-exec - use full paths or `${path.module}`
- SSH key path must be explicitly passed to modules that need it
