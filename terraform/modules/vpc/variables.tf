variable "cluster_name" {
  description = "Name of the cluster"
  type        = string
}

variable "network_zone" {
  description = "Network zone for the private network"
  type        = string
}

variable "network_cidr" {
  description = "CIDR for the private network"
  type        = string
}

variable "subnet_cidr" {
  description = "CIDR for the subnet"
  type        = string
}

variable "location" {
  description = "Hetzner Cloud location"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}