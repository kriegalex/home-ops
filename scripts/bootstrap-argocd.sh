#!/usr/bin/env bash
set -Eeuo pipefail

source "$(dirname "${0}")/lib/common.sh"

export LOG_LEVEL="info"
export ROOT_DIR="$(git rev-parse --show-toplevel)"

# Talos requires the nodes to be 'Ready=False' before applying resources
function wait_for_nodes() {
    log debug "Waiting for nodes to be available"

    # Skip waiting if all nodes are 'Ready=True'
    if kubectl wait nodes --for=condition=Ready=True --all --timeout=10s &>/dev/null; then
        log info "Nodes are available and ready, skipping wait for nodes"
        return
    fi

    # Wait for all nodes to be 'Ready=False'
    until kubectl wait nodes --for=condition=Ready=False --all --timeout=10s &>/dev/null; do
        log info "Nodes are not available, waiting for nodes to be available. Retrying in 10 seconds..."
        sleep 10
    done
}

# Apply Cilium CNI first (required for cluster networking)
function apply_cilium() {
    log info "Installing Cilium CNI"

    local -r cilium_values="${ROOT_DIR}/kubernetes/argocd/applications/kube-system/cilium.yaml"

    if [[ ! -f "${cilium_values}" ]]; then
        log error "Cilium values file not found" "file=${cilium_values}"
        return 1
    fi

    # Extract Helm chart details from ArgoCD Application
    local chart_repo=$(yq '.spec.source.repoURL' "${cilium_values}")
    local chart_version=$(yq '.spec.source.targetRevision' "${cilium_values}")

    # Install Cilium via Helm
    log info "Installing Cilium ${chart_version}"
    helm upgrade --install cilium cilium \
        --repo https://helm.cilium.io/ \
        --version "${chart_version}" \
        --namespace kube-system \
        --values <(yq '.spec.source.helm.valuesObject' "${cilium_values}" -o=yaml) \
        --wait

    log info "Cilium installed successfully"
}

# Apply CoreDNS
function apply_coredns() {
    log info "Installing CoreDNS"

    local -r coredns_values="${ROOT_DIR}/kubernetes/argocd/applications/kube-system/coredns.yaml"

    if [[ ! -f "${coredns_values}" ]]; then
        log error "CoreDNS values file not found" "file=${coredns_values}"
        return 1
    fi

    # Extract Helm chart details
    local chart_repo=$(yq '.spec.source.repoURL' "${coredns_values}")
    local chart_version=$(yq '.spec.source.targetRevision' "${coredns_values}")

    # Install CoreDNS via Helm
    log info "Installing CoreDNS ${chart_version}"
    helm upgrade --install coredns coredns \
        --repo "oci://${chart_repo}" \
        --version "${chart_version}" \
        --namespace kube-system \
        --values <(yq '.spec.source.helm.valuesObject' "${coredns_values}" -o=yaml) \
        --wait

    log info "CoreDNS installed successfully"
}

# Install ArgoCD
function install_argocd() {
    log info "Installing ArgoCD"

    # Create namespace
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

    # Install ArgoCD via Helm
    log info "Adding ArgoCD Helm repository"
    helm repo add argo https://argoproj.github.io/argo-helm
    helm repo update

    local -r argocd_values="${ROOT_DIR}/kubernetes/apps/argocd/argocd/app/values.yaml"

    if [[ ! -f "${argocd_values}" ]]; then
        log error "ArgoCD values file not found" "file=${argocd_values}"
        return 1
    fi

    log info "Installing ArgoCD Helm chart"
    helm upgrade --install argocd argo/argo-cd \
        --namespace argocd \
        --values "${argocd_values}" \
        --wait \
        --timeout 10m

    log info "ArgoCD installed successfully"
}

# Apply SOPS secrets
function apply_sops_secrets() {
    log info "Applying SOPS-encrypted secrets"

    # Apply SOPS age key secret (required for ArgoCD to decrypt secrets)
    local -r age_secret="${ROOT_DIR}/kubernetes/components/sops/cluster-secrets.sops.yaml"

    if [[ -f "${age_secret}" ]]; then
        log info "Applying age encryption key secret"
        sops exec-file "${age_secret}" "kubectl apply --namespace argocd --filename {}"
    else
        log warn "Age secret not found, skipping" "file=${age_secret}"
    fi

    # Apply Gitea deploy key secret (required for ArgoCD to access Git repository)
    local -r deploy_key="${ROOT_DIR}/kubernetes/apps/argocd/argocd/app/secret.sops.yaml"

    if [[ -f "${deploy_key}" ]]; then
        log info "Applying Gitea deploy key secret"
        sops exec-file "${deploy_key}" "kubectl apply --namespace argocd --filename {}"
    else
        log warn "Gitea deploy key not found, skipping" "file=${deploy_key}"
    fi

    log info "Secrets applied successfully"
}

# Deploy root App-of-Apps
function deploy_root_app() {
    log info "Deploying ArgoCD root App-of-Apps"

    local -r root_app="${ROOT_DIR}/kubernetes/apps/argocd/app-of-apps/app/root-app.yaml"

    if [[ ! -f "${root_app}" ]]; then
        log error "Root App-of-Apps not found" "file=${root_app}"
        return 1
    fi

    kubectl apply --namespace argocd --filename "${root_app}"

    log info "Root App-of-Apps deployed successfully"
}

# Sync all applications
function sync_applications() {
    log info "Syncing all ArgoCD applications"

    # Wait for ArgoCD to be ready
    log info "Waiting for ArgoCD server to be ready"
    kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

    # Sync the root app (which will sync all child applications)
    log info "Triggering sync of cluster-apps"
    argocd app sync cluster-apps --grpc-web || log warn "Failed to sync via CLI, applications will sync automatically"

    log info "Application sync initiated"
}

# Main bootstrap sequence
function main() {
    log info "Starting ArgoCD bootstrap process"

    # Stage 1: Wait for nodes
    wait_for_nodes

    # Stage 2: Install core networking
    apply_cilium
    apply_coredns

    # Stage 3: Install ArgoCD
    install_argocd

    # Stage 4: Apply secrets
    apply_sops_secrets

    # Stage 5: Deploy root App-of-Apps
    deploy_root_app

    # Stage 6: Sync all applications
    sync_applications

    log info "Bootstrap process completed successfully!"
    log info "Monitor application deployment with: kubectl get pods -A --watch"
    log info "Or use ArgoCD UI: kubectl port-forward svc/argocd-server -n argocd 8080:443"
}

main "$@"
