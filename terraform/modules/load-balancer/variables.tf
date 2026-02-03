variable "cluster_name" {
  description = "Name of the cluster"
  type        = string
}

variable "load_balancer_type" {
  description = "Type of load balancer"
  type        = string
  default     = "lb11"
}

variable "location" {
  description = "Hetzner Cloud location"
  type        = string
}

variable "network_id" {
  description = "ID of the network"
  type        = string
}

variable "subnet_cidr" {
  description = "CIDR of the subnet for IP allocation"
  type        = string
  default     = "10.0.1.0/24"
}

variable "control_plane_ids" {
  description = "List of control plane server IDs"
  type        = list(string)
}

variable "worker_node_ids" {
  description = "List of worker node server IDs"
  type        = list(string)
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}