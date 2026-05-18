#!/usr/bin/env bash
set -euo pipefail

echo "Starting uninstallation..."

#######################################
# Remove ArgoCD CLI
#######################################
echo "Removing ArgoCD CLI..."
if [ -f /usr/local/bin/argocd ]; then
  sudo rm -f /usr/local/bin/argocd
  echo "ArgoCD CLI removed."
else
  echo "ArgoCD CLI not found, skipping."
fi

#######################################
# Remove kubeconfig
#######################################
echo "Removing Kubeconfig..."
if [ -f "$HOME/.kube/config" ]; then
  rm -f "$HOME/.kube/config"
  echo "Kubeconfig removed."
else
  echo "Kubeconfig not found, skipping."
fi

# Optionally, remove the .kube directory if it is empty after config removal
if [ -d "$HOME/.kube" ] && [ -z "$(ls -A "$HOME/.kube")" ]; then
  rmdir "$HOME/.kube"
fi

#######################################
# Uninstall K3s
#######################################
echo "Uninstalling K3s..."
# The k3s-uninstall.sh script will tear down the cluster, removing all namespaces, 
# deployments (ArgoCD, cert-manager, sealed-secrets), and configurations.
if command -v k3s-uninstall.sh >/dev/null 2>&1; then
  sudo k3s-uninstall.sh
elif [ -f /usr/local/bin/k3s-uninstall.sh ]; then
  sudo /usr/local/bin/k3s-uninstall.sh
else
  echo "k3s-uninstall.sh not found. K3s might already be uninstalled."
fi

echo ""
echo "Uninstallation complete."
