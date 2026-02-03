# Kubernetes and Helm providers configured from generated kubeconfig
# These providers connect directly to the cluster without SSH

locals {
  kubeconfig = try(yamldecode(module.control_plane.kubeconfig), {})
}

provider "kubernetes" {
  host                   = try(local.kubeconfig.clusters[0].cluster.server, "")
  cluster_ca_certificate = try(base64decode(local.kubeconfig.clusters[0].cluster["certificate-authority-data"]), "")
  client_certificate     = try(base64decode(local.kubeconfig.users[0].user["client-certificate-data"]), "")
  client_key             = try(base64decode(local.kubeconfig.users[0].user["client-key-data"]), "")
}

provider "helm" {
  kubernetes {
    host                   = try(local.kubeconfig.clusters[0].cluster.server, "")
    cluster_ca_certificate = try(base64decode(local.kubeconfig.clusters[0].cluster["certificate-authority-data"]), "")
    client_certificate     = try(base64decode(local.kubeconfig.users[0].user["client-certificate-data"]), "")
    client_key             = try(base64decode(local.kubeconfig.users[0].user["client-key-data"]), "")
  }
}
