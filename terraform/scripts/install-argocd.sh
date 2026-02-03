#!/bin/bash
set -eu

# Environment variables are passed from Terraform's environment parameter
# KUBECONFIG, ARGOCD_NAMESPACE, and CLUSTER_NAME should be set

echo "Installing ArgoCD in namespace ${ARGOCD_NAMESPACE}..."

# Create namespace
kubectl create namespace ${ARGOCD_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Install ArgoCD
kubectl apply -n ${ARGOCD_NAMESPACE} -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
echo "Waiting for ArgoCD pods to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n ${ARGOCD_NAMESPACE} --timeout=300s

# Patch ArgoCD server to use LoadBalancer (if available) or NodePort
kubectl patch svc argocd-server -n ${ARGOCD_NAMESPACE} -p '{"spec": {"type": "LoadBalancer"}}'

# Get initial admin password
echo ""
echo "ArgoCD installation complete!"
echo "================================"
echo "ArgoCD is installed in namespace: ${ARGOCD_NAMESPACE}"
echo ""
echo "To get the initial admin password, run:"
echo "kubectl -n ${ARGOCD_NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo ""
echo "To access ArgoCD UI:"
echo "1. Get the external IP: kubectl -n ${ARGOCD_NAMESPACE} get svc argocd-server"
echo "2. Login with username: admin"
echo ""

# Optional: Install ArgoCD CLI
echo "To install ArgoCD CLI locally, run:"
echo "curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64"
echo "chmod +x /usr/local/bin/argocd"
