variable "cluster_name" {
  description = "Name of the cluster"
  type        = string
}

variable "allowed_ssh_ips" {
  description = "List of IP addresses allowed to SSH"
  type        = list(string)
  default     = []
}

variable "allowed_api_ips" {
  description = "List of IP addresses allowed to access K8s API"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}