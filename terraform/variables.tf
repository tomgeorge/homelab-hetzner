# Hetzner Cloud Configuration
variable "hcloud_token" {
  description = "Hetzner Cloud API token"
  type        = string
  sensitive   = true
}

# Cluster Configuration
variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
  default     = "homelab"
}

variable "kubernetes_version" {
  description = "Kubernetes version to install (K3s version)"
  type        = string
  default     = "v1.29.0+k3s1"
}

# Location Configuration
variable "location" {
  description = "Hetzner Cloud location"
  type        = string
  default     = "fsn1" # Falkenstein, Germany (cheapest)
  # Other options: hel1 (Helsinki), nbg1 (Nuremberg), ash (Ashburn)
}

# Network Configuration
variable "network_zone" {
  description = "Network zone for the private network"
  type        = string
  default     = "eu-central"
}

variable "network_cidr" {
  description = "CIDR for the private network"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR for the subnet"
  type        = string
  default     = "10.0.1.0/24"
}

# Server Configuration
variable "control_plane_count" {
  description = "Number of control plane nodes"
  type        = number
  default     = 1
  validation {
    condition     = var.control_plane_count % 2 == 1 && var.control_plane_count >= 1
    error_message = "Control plane count must be an odd number (1, 3, or 5 for HA)."
  }
}

variable "control_plane_type" {
  description = "Server type for control plane nodes"
  type        = string
  default     = "cx33" # 4 vCPU, 8GB RAM
}

variable "worker_node_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 3
  validation {
    condition     = var.worker_node_count >= 1
    error_message = "At least 1 worker node is required."
  }
}

variable "worker_node_type" {
  description = "Server type for worker nodes"
  type        = string
  default     = "cx33" # 4 vCPU, 8GB RAM
  # Options: cpx11 (2vCPU, 2GB), cpx21 (3vCPU, 4GB), cpx31 (4vCPU, 8GB), cpx41 (8vCPU, 16GB)
}

# Storage Configuration
variable "enable_persistent_volumes" {
  description = "Enable persistent volume support with Hetzner CSI"
  type        = bool
  default     = true
}

variable "volume_size" {
  description = "Default size for persistent volumes in GB"
  type        = number
  default     = 50
}

# Load Balancer Configuration
variable "enable_load_balancer" {
  description = "Enable Hetzner Load Balancer for ingress"
  type        = bool
  default     = true
}

variable "load_balancer_type" {
  description = "Load balancer type"
  type        = string
  default     = "lb11" # Supports up to 5 targets
  # Options: lb11 (5 targets), lb21 (25 targets), lb31 (75 targets)
}

# ArgoCD Configuration
variable "install_argocd" {
  description = "Install ArgoCD for GitOps"
  type        = bool
  default     = true
}

variable "argocd_namespace" {
  description = "Namespace for ArgoCD"
  type        = string
  default     = "argocd"
}

# Tailscale Configuration
variable "install_tailscale" {
  description = "Install Tailscale operator for exposing services to tailnet"
  type        = bool
  default     = false
}

variable "tailscale_oauth_client_id" {
  description = "Tailscale OAuth client ID (required if install_tailscale is true)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "tailscale_oauth_client_secret" {
  description = "Tailscale OAuth client secret (required if install_tailscale is true)"
  type        = string
  default     = ""
  sensitive   = true
}

# SSH Configuration
variable "ssh_public_key_path" {
  description = "Path to existing SSH public key (optional, will generate if not provided)"
  type        = string
  default     = ""
}

variable "ssh_private_key_path" {
  description = "Path to existing SSH private key (optional, will generate if not provided)"
  type        = string
  default     = ""
}

# Firewall Configuration
variable "enable_firewall" {
  description = "Enable Hetzner Cloud Firewall"
  type        = bool
  default     = true
}

variable "allowed_ssh_ips" {
  description = "List of IP addresses allowed to SSH (empty = all)"
  type        = list(string)
  default     = [] # Empty means allow from anywhere. Add your IP for security.
}

variable "allowed_api_ips" {
  description = "List of IP addresses allowed to access K8s API (empty = all)"
  type        = list(string)
  default     = [] # Empty means allow from anywhere. Add your IP for security.
}

# Cost Optimization
variable "server_configuration" {
  description = "Predefined server configuration profile"
  type        = string
  default     = "recommended"
  validation {
    condition     = contains(["budget", "recommended", "performance"], var.server_configuration)
    error_message = "Server configuration must be 'budget', 'recommended', or 'performance'."
  }
}

# Tags
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    managed_by = "terraform"
    project    = "homelab"
  }
}

