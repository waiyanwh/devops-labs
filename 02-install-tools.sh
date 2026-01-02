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
    kubectl apply -f "${SCRIPT_DIR}/k8s/argocd-ingress.yaml"

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
    kubectl apply -f "${SCRIPT_DIR}/k8s/grafana-ingress.yaml"

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
    kubectl apply -f "${SCRIPT_DIR}/k8s/logging/datasource.yaml"
    
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
# KEDA Installation (Event-Driven Scaling)
# ============================================================================

install_keda() {
    echo_header "Installing KEDA"

    # Create namespace
    kubectl create namespace keda --dry-run=client -o yaml | kubectl apply -f -

    # Add KEDA Helm repo
    echo_info "Adding KEDA Helm repository..."
    helm repo add kedacore https://kedacore.github.io/charts 2>/dev/null || true
    helm repo update

    # Install KEDA
    echo_info "Installing KEDA via Helm (version ${KEDA_CHART_VERSION})..."
    helm upgrade --install keda kedacore/keda \
        --namespace keda \
        --version "${KEDA_CHART_VERSION}" \
        --wait --timeout 5m

    echo_info "KEDA installed successfully!"
}

# ============================================================================
# RabbitMQ Cluster Operator Installation
# ============================================================================

install_rabbitmq() {
    echo_header "Installing RabbitMQ Cluster Operator"

    # Install RabbitMQ Cluster Operator
    echo_info "Installing RabbitMQ Cluster Operator..."
    kubectl apply -f "https://github.com/rabbitmq/cluster-operator/releases/latest/download/cluster-operator.yml"

    # Wait for operator to be ready
    echo_info "Waiting for RabbitMQ Operator to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/rabbitmq-cluster-operator -n rabbitmq-system

    # Create message-queue namespace
    kubectl create namespace message-queue --dry-run=client -o yaml | kubectl apply -f -

    # Deploy RabbitMQ cluster
    echo_info "Deploying RabbitMQ cluster..."
    kubectl apply -f "${SCRIPT_DIR}/k8s/infrastructure/rabbitmq-cluster.yaml"

    # Apply Ingress
    echo_info "Applying RabbitMQ Ingress..."
    kubectl apply -f "${SCRIPT_DIR}/k8s/infrastructure/rabbitmq-ingress.yaml"

    # Wait for RabbitMQ to be ready
    echo_info "Waiting for RabbitMQ cluster to be ready..."
    kubectl wait --for=condition=AllReplicasReady --timeout=300s rabbitmqcluster/rabbitmq -n message-queue

    # Create rabbitmq-creds secret in app namespace
    echo_info "Creating rabbitmq-creds in 'app' namespace..."
    kubectl create namespace app --dry-run=client -o yaml | kubectl apply -f -

    # Get credentials from RabbitMQ default user secret
    RMQ_USER=$(kubectl get secret rabbitmq-default-user -n message-queue -o jsonpath='{.data.username}' | base64 -d)
    RMQ_PASS=$(kubectl get secret rabbitmq-default-user -n message-queue -o jsonpath='{.data.password}' | base64 -d)
    RMQ_HOST="rabbitmq.message-queue.svc"
    RMQ_URI="amqp://${RMQ_USER}:${RMQ_PASS}@${RMQ_HOST}:5672/"

    kubectl create secret generic rabbitmq-creds \
        --namespace app \
        --from-literal=host="${RMQ_HOST}" \
        --from-literal=username="${RMQ_USER}" \
        --from-literal=password="${RMQ_PASS}" \
        --from-literal=uri="${RMQ_URI}" \
        --dry-run=client -o yaml | kubectl apply -f -

    echo_info "RabbitMQ installed successfully!"
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              RabbitMQ Credentials                          ║${NC}"
    echo -e "${GREEN}╠════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}  URL:      http://rabbitmq.localhost                        ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  Username: ${RMQ_USER}   ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  Password: ${RMQ_PASS}   ${GREEN}║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ============================================================================
# Local Docker Registry Installation
# ============================================================================

install_registry() {
    echo_header "Installing Local Docker Registry"

    # Create namespace
    kubectl create namespace "${CI_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

    # Apply registry manifests
    echo_info "Deploying Docker Registry..."
    kubectl apply -f "${SCRIPT_DIR}/k8s/ci/registry.yaml"

    # Wait for registry to be ready
    echo_info "Waiting for Registry to be ready..."
    kubectl wait --for=condition=available --timeout=120s deployment/registry -n "${CI_NAMESPACE}"

    echo_info "Local Docker Registry installed successfully!"
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              Docker Registry Info                          ║${NC}"
    echo -e "${GREEN}╠════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}  Internal: ${REGISTRY_HOSTNAME}:${REGISTRY_PORT}      ${GREEN}║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ============================================================================
# Jenkins Installation
# ============================================================================

install_jenkins() {
    echo_header "Installing Jenkins"

    # Ensure namespace exists
    kubectl create namespace "${CI_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

    # Add Jenkins Helm repo (official jenkinsci repo)
    echo_info "Adding Jenkins Helm repository..."
    helm repo add jenkinsci https://charts.jenkins.io 2>/dev/null || true
    helm repo update

    # Install Jenkins (latest version)
    echo_info "Installing Jenkins via Helm..."
    helm upgrade --install jenkins jenkinsci/jenkins \
        --namespace "${CI_NAMESPACE}" \
        -f "${SCRIPT_DIR}/k8s/ci/jenkins-values.yaml" \
        --wait --timeout 10m

    echo_info "Jenkins installed successfully!"

    # Apply IngressRoute
    echo_info "Applying Jenkins IngressRoute..."
    kubectl apply -f "${SCRIPT_DIR}/k8s/ci/jenkins-ingress.yaml"

    # Wait for Jenkins pod to be ready
    echo_info "Waiting for Jenkins to be ready..."
    kubectl wait --for=condition=ready --timeout=300s pod -l app.kubernetes.io/component=jenkins-controller -n "${CI_NAMESPACE}" || true

    # Get initial admin password
    echo_info "Retrieving Jenkins admin password..."
    sleep 5
    JENKINS_PASSWORD=$(kubectl exec --namespace "${CI_NAMESPACE}" -it svc/jenkins -c jenkins -- /bin/cat /run/secrets/additional/chart-admin-password 2>/dev/null || echo "pending")
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              Jenkins Credentials                           ║${NC}"
    echo -e "${GREEN}╠════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}  URL:      http://${JENKINS_HOSTNAME}                        ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  Username: admin                                            ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  Password: ${JENKINS_PASSWORD}                     ${GREEN}║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo_info "If password shows 'pending', run this to get it:"
    echo "  kubectl exec --namespace ${CI_NAMESPACE} -it svc/jenkins -c jenkins -- /bin/cat /run/secrets/additional/chart-admin-password"
    echo ""
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

    # Test Jenkins
    echo -n "  Jenkins (${JENKINS_HOSTNAME}): "
    JENKINS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: ${JENKINS_HOSTNAME}" http://127.0.0.1 2>/dev/null || echo "000")
    if [ "$JENKINS_STATUS" = "200" ] || [ "$JENKINS_STATUS" = "403" ]; then
        echo -e "${GREEN}✓ Reachable (HTTP $JENKINS_STATUS)${NC}"
    else
        echo -e "${YELLOW}⚠ HTTP $JENKINS_STATUS (may still be starting)${NC}"
    fi

    echo ""
    echo_info "CI pods:"
    kubectl get pods -n "${CI_NAMESPACE}"
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
    echo "  CI Namespace:             ${CI_NAMESPACE}"
    echo ""

    check_prerequisites
    install_argocd
    install_prometheus_stack
    install_loki
    install_keda
    install_rabbitmq
    install_registry
    install_jenkins
    verify_installation

    echo ""
    echo "============================================================"
    echo -e "  ${GREEN}Installation Complete!${NC}"
    echo "============================================================"
    echo ""
    echo "Access your services:"
    echo "  • ArgoCD:  http://${ARGOCD_HOSTNAME}   (${ARGOCD_ADMIN_USER} / <password above>)"
    echo "  • Grafana: http://${GRAFANA_HOSTNAME}  (${GRAFANA_ADMIN_USER} / ${GRAFANA_ADMIN_PASSWORD})"
    echo "  • Jenkins: http://${JENKINS_HOSTNAME}  (admin / <password above>)"
    echo ""
    echo "Add to /etc/hosts if needed:"
    echo "  127.0.0.1 ${ARGOCD_HOSTNAME} ${GRAFANA_HOSTNAME} rabbitmq.localhost ${JENKINS_HOSTNAME}"
    echo ""
}

main "$@"
