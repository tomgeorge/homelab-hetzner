variable "cluster_name" {
  description = "Name of the cluster"
  type        = string
}

variable "node_count" {
  description = "Number of control plane nodes"
  type        = number
  default     = 1
}

variable "server_type" {
  description = "Server type for control plane nodes"
  type        = string
}

variable "location" {
  description = "Hetzner Cloud location"
  type        = string
}

variable "network_id" {
  description = "ID of the network to attach servers to"
  type        = string
}

variable "subnet_id" {
  description = "ID of the subnet"
  type        = string
}

variable "subnet_cidr" {
  description = "CIDR of the subnet for IP allocation"
  type        = string
  default     = "10.0.1.0/24"
}

variable "ssh_key_id" {
  description = "ID of the SSH key"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Path to existing SSH private key (optional, will generate if not provided)"
  type        = string
  default     = ""
}

variable "k3s_token" {
  description = "Token for K3s cluster join"
  type        = string
  sensitive   = true
}

variable "kubernetes_version" {
  description = "K3s version to install"
  type        = string
}

variable "firewall_ids" {
  description = "List of firewall IDs to attach"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

