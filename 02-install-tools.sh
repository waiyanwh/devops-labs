#!/bin/bash

# ============================================================================
# GitOps and Observability Stack Installation Script
# ============================================================================
# Installs ArgoCD and Kube-Prometheus-Stack with configurable options.
# All settings are loaded from config.env
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration
if [ -f "${SCRIPT_DIR}/config.env" ]; then
    source "${SCRIPT_DIR}/config.env"
else
    echo "Error: config.env not found. Please create it from config.env.example"
    exit 1
fi

# ============================================================================
# Prerequisites Check
# ============================================================================

check_prerequisites() {
    echo_header "Checking Prerequisites"

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        echo_error "kubectl is not installed"
        exit 1
    fi

    # Check helm
    if ! command -v helm &> /dev/null; then
        echo_error "Helm is not installed."
        echo_info "Install Helm with:"
        echo "  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
        exit 1
    fi

    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        echo_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi

    echo_info "kubectl: $(kubectl version --client --short 2>/dev/null || kubectl version --client | head -1)"
    echo_info "helm: $(helm version --short)"
    echo_info "Cluster connection: OK"
}

# ============================================================================
# ArgoCD Installation
# ============================================================================

install_argocd() {
    echo_header "Installing ArgoCD"

    # Create namespace
    kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

    # Add ArgoCD Helm repo
    echo_info "Adding ArgoCD Helm repository..."
    helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
    helm repo update

    # Install ArgoCD
    echo_info "Installing ArgoCD via Helm (version ${ARGOCD_CHART_VERSION})..."
    helm upgrade --install argocd argo/argo-cd \
        --namespace "${ARGOCD_NAMESPACE}" \
        --version "${ARGOCD_CHART_VERSION}" \
        --set server.service.type=ClusterIP \
        --set server.extraArgs="{--insecure}" \
        --set configs.params."server\.insecure"=true \
        --wait --timeout 5m

    echo_info "ArgoCD installed successfully!"

    # Apply IngressRoute
    echo_info "Applying ArgoCD IngressRoute..."
    kubectl apply -f "${SCRIPT_DIR}/manifests/argocd-ingress.yaml"

    # Wait for ArgoCD server to be ready
    echo_info "Waiting for ArgoCD server to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n "${ARGOCD_NAMESPACE}"

    # Get initial admin password
    echo_info "Retrieving ArgoCD admin password..."
    sleep 5
    ARGOCD_PASSWORD=$(kubectl -n "${ARGOCD_NAMESPACE}" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)
    
    if [ -n "$ARGOCD_PASSWORD" ]; then
        echo ""
        echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║              ArgoCD Credentials                            ║${NC}"
        echo -e "${GREEN}╠════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${GREEN}║${NC}  URL:      http://${ARGOCD_HOSTNAME}                         ${GREEN}║${NC}"
        echo -e "${GREEN}║${NC}  Username: ${ARGOCD_ADMIN_USER}                                           ${GREEN}║${NC}"
        echo -e "${GREEN}║${NC}  Password: ${ARGOCD_PASSWORD}                              ${GREEN}║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
    else
        echo_warn "Could not retrieve ArgoCD password. Try:"
        echo "  kubectl -n ${ARGOCD_NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
    fi
}

# ============================================================================
# Kube-Prometheus-Stack Installation
# ============================================================================

install_prometheus_stack() {
    echo_header "Installing Kube-Prometheus-Stack"

    # Create namespace
    kubectl create namespace "${MONITORING_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

    # Add Prometheus Helm repo
    echo_info "Adding Prometheus community Helm repository..."
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
    helm repo update

    # Install kube-prometheus-stack
    echo_info "Installing kube-prometheus-stack via Helm (version ${PROMETHEUS_STACK_VERSION})..."
    helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
        --namespace "${MONITORING_NAMESPACE}" \
        --version "${PROMETHEUS_STACK_VERSION}" \
        --set grafana.adminPassword="${GRAFANA_ADMIN_PASSWORD}" \
        --set grafana.service.type=ClusterIP \
        --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
        --set nodeExporter.enabled=false \
        --set prometheusNodeExporter.enabled=false \
        --wait --timeout 10m

    echo_info "Kube-prometheus-stack installed successfully!"

    # Apply IngressRoute
    echo_info "Applying Grafana IngressRoute..."
    kubectl apply -f "${SCRIPT_DIR}/manifests/grafana-ingress.yaml"

    # Wait for Grafana to be ready
    echo_info "Waiting for Grafana to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/kube-prometheus-stack-grafana -n "${MONITORING_NAMESPACE}"

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              Grafana Credentials                           ║${NC}"
    echo -e "${GREEN}╠════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}  URL:      http://${GRAFANA_HOSTNAME}                         ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  Username: ${GRAFANA_ADMIN_USER}                                            ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  Password: ${GRAFANA_ADMIN_PASSWORD}                                            ${GREEN}║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ============================================================================
# Loki Stack Installation (Logging)
# ============================================================================

install_loki() {
    echo_header "Installing Loki Stack (Logging)"

    # Add Grafana repo
    echo_info "Adding Grafana Helm repository..."
    helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
    helm repo update

    # Install Loki Stack
    echo_info "Installing Loki Stack via Helm (version ${LOKI_STACK_VERSION})..."
    helm upgrade --install loki grafana/loki-stack \
        --namespace "${MONITORING_NAMESPACE}" \
        --version "${LOKI_STACK_VERSION}" \
        --set grafana.enabled=false \
        --set prometheus.enabled=false \
        --set promtail.enabled=true \
        --set loki.isDefault=false \
        --wait --timeout 10m

    echo_info "Loki Stack installed successfully!"

    # Apply Datasource
    echo_info "Applying Loki Datasource..."
    kubectl apply -f "${SCRIPT_DIR}/manifests/logging/datasource.yaml"
    
    echo_info "Applying Cluster Logs Dashboard..."
    # Apply dashboard to monitoring, hoping sidecar picks it up from there (it should)
    # The artifact was created in gitops-root/templates/loki-dashboard.yaml (which syncs to app)
    # But for manual tool install, let's also apply it here.
    # Note: earlier I made gitops-root/templates/loki-dashboard.yaml which defines it in 'app' namespace.
    # Typically sidecar scans all namespaces or specific ones. 
    # Let's apply it directly to cluster.
    kubectl apply -f "${SCRIPT_DIR}/gitops-root/templates/loki-dashboard.yaml"
}

# ============================================================================
# Verification
# ============================================================================

verify_installation() {
    echo_header "Verifying Installation"

    echo_info "ArgoCD pods:"
    kubectl get pods -n "${ARGOCD_NAMESPACE}"

    echo ""
    echo_info "Monitoring pods:"
    kubectl get pods -n "${MONITORING_NAMESPACE}"

    echo ""
    echo_info "IngressRoutes:"
    kubectl get ingressroute -A

    echo ""
    echo_info "Testing endpoints..."
    
    # Test ArgoCD
    echo -n "  ArgoCD (${ARGOCD_HOSTNAME}): "
    ARGOCD_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: ${ARGOCD_HOSTNAME}" http://127.0.0.1 2>/dev/null || echo "000")
    if [ "$ARGOCD_STATUS" = "200" ] || [ "$ARGOCD_STATUS" = "307" ]; then
        echo -e "${GREEN}✓ Reachable (HTTP $ARGOCD_STATUS)${NC}"
    else
        echo -e "${YELLOW}⚠ HTTP $ARGOCD_STATUS (may still be starting)${NC}"
    fi

    # Test Grafana
    echo -n "  Grafana (${GRAFANA_HOSTNAME}): "
    GRAFANA_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: ${GRAFANA_HOSTNAME}" http://127.0.0.1 2>/dev/null || echo "000")
    if [ "$GRAFANA_STATUS" = "200" ] || [ "$GRAFANA_STATUS" = "302" ]; then
        echo -e "${GREEN}✓ Reachable (HTTP $GRAFANA_STATUS)${NC}"
    else
        echo -e "${YELLOW}⚠ HTTP $GRAFANA_STATUS (may still be starting)${NC}"
    fi
}

# ============================================================================
# Main
# ============================================================================

main() {
    echo ""
    echo "============================================================"
    echo "  GitOps & Observability Stack Installation"
    echo "============================================================"
    echo ""
    echo "Configuration:"
    echo "  ArgoCD Chart Version:     ${ARGOCD_CHART_VERSION}"
    echo "  Prometheus Chart Version: ${PROMETHEUS_STACK_VERSION}"
    echo "  ArgoCD Namespace:         ${ARGOCD_NAMESPACE}"
    echo "  Monitoring Namespace:     ${MONITORING_NAMESPACE}"
    echo ""

    check_prerequisites
    install_argocd
    install_prometheus_stack
    install_loki
    verify_installation

    echo ""
    echo "============================================================"
    echo -e "  ${GREEN}Installation Complete!${NC}"
    echo "============================================================"
    echo ""
    echo "Access your services:"
    echo "  • ArgoCD:  http://${ARGOCD_HOSTNAME}   (${ARGOCD_ADMIN_USER} / <password above>)"
    echo "  • Grafana: http://${GRAFANA_HOSTNAME}  (${GRAFANA_ADMIN_USER} / ${GRAFANA_ADMIN_PASSWORD})"
    echo ""
    echo "Add to /etc/hosts if needed:"
    echo "  127.0.0.1 ${ARGOCD_HOSTNAME} ${GRAFANA_HOSTNAME}"
    echo ""
}

main "$@"
