#!/bin/bash

# ============================================================================
# 3-Tier Application Build and Deploy Script
# ============================================================================
# Builds Docker images, imports them into k3d, and deploys to Kubernetes.
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
# Build Docker Images
# ============================================================================

build_images() {
    echo_header "Building Docker Images"

    # Build Backend
    echo_info "Building backend image (${BACKEND_FULL_IMAGE})..."
    docker build -t "${BACKEND_FULL_IMAGE}" "${SCRIPT_DIR}/src/backend/"
    echo_info "Backend image built: ${BACKEND_FULL_IMAGE}"

    # Build Frontend
    echo_info "Building frontend image (${FRONTEND_FULL_IMAGE})..."
    docker build -t "${FRONTEND_FULL_IMAGE}" "${SCRIPT_DIR}/src/frontend/"
    echo_info "Frontend image built: ${FRONTEND_FULL_IMAGE}"

    # Build Worker
    echo_info "Building worker image (lab-worker:v1)..."
    docker build -t "lab-worker:v1" "${SCRIPT_DIR}/src/worker/"
    echo_info "Worker image built: lab-worker:v1"
}

# Determine k3d binary
K3D_BIN="k3d"
if [ -f "${SCRIPT_DIR}/k3d" ]; then
    K3D_BIN="${SCRIPT_DIR}/k3d"
    echo_info "Using local k3d binary: ${K3D_BIN}"
fi

# ============================================================================
# Import Images into k3d
# ============================================================================

import_images() {
    echo_header "Importing Images into k3d Cluster"

    echo_info "Importing ${BACKEND_FULL_IMAGE}..."
    ${K3D_BIN} image import "${BACKEND_FULL_IMAGE}" -c "${CLUSTER_NAME}"

    echo_info "Importing ${FRONTEND_FULL_IMAGE}..."
    ${K3D_BIN} image import "${FRONTEND_FULL_IMAGE}" -c "${CLUSTER_NAME}"

    echo_info "Importing lab-worker:v1..."
    ${K3D_BIN} image import "lab-worker:v1" -c "${CLUSTER_NAME}"


    echo_info "Images imported successfully!"
}

# ============================================================================
# Deploy Application
# ============================================================================

deploy_app() {
    echo_header "Deploying Application to Kubernetes"

    # Create namespace first
    echo_info "Creating namespace '${APP_NAMESPACE}'..."
    kubectl apply -f "${SCRIPT_DIR}/k8s/app/namespace.yaml"

    # Apply Grafana dashboard to monitoring namespace
    echo_info "Deploying Grafana dashboard..."
    kubectl apply -f "${SCRIPT_DIR}/k8s/app/grafana-dashboard.yaml"

    # Deploy in order: Database -> Backend -> Frontend -> Ingress
    echo_info "Deploying PostgreSQL..."
    kubectl apply -f "${SCRIPT_DIR}/k8s/app/postgres.yaml"

    echo_info "Waiting for PostgreSQL to be ready..."
    kubectl wait --for=condition=available --timeout=120s deployment/postgres -n "${APP_NAMESPACE}"

    echo_info "Deploying Backend..."
    kubectl apply -f "${SCRIPT_DIR}/k8s/app/backend.yaml"

    echo_info "Deploying Frontend..."
    kubectl apply -f "${SCRIPT_DIR}/k8s/app/frontend.yaml"

    echo_info "Deploying Worker..."
    if [ -f "${SCRIPT_DIR}/k8s/app/worker.yaml" ]; then
        kubectl apply -f "${SCRIPT_DIR}/k8s/app/worker.yaml"
    else
        echo_warn "Worker manifest not found!"
    fi


    echo_info "Creating IngressRoutes..."
    kubectl apply -f "${SCRIPT_DIR}/k8s/app/ingress.yaml"

    echo_info "Creating ServiceMonitor..."
    kubectl apply -f "${SCRIPT_DIR}/k8s/app/servicemonitor.yaml"

    echo_info "Creating KEDA ScaledObject for Worker..."
    kubectl apply -f "${SCRIPT_DIR}/k8s/app/rabbitmq-scaledobject.yaml"

    echo_info "Waiting for all deployments to be ready..."
    kubectl wait --for=condition=available --timeout=120s deployment/backend -n "${APP_NAMESPACE}"
    kubectl wait --for=condition=available --timeout=120s deployment/frontend -n "${APP_NAMESPACE}"
    # Worker might scale to 0, so don't wait for it if replicas=0
}


# ============================================================================
# Verify Deployment
# ============================================================================

verify_deployment() {
    echo_header "Verifying Deployment"

    echo_info "Pods status:"
    kubectl get pods -n "${APP_NAMESPACE}"

    echo ""
    echo_info "Services:"
    kubectl get svc -n "${APP_NAMESPACE}"

    echo ""
    echo_info "IngressRoutes:"
    kubectl get ingressroute -n "${APP_NAMESPACE}"

    echo ""
    echo_info "Testing endpoints..."
    sleep 3

    # Test API
    echo -n "  API (${API_HOSTNAME}): "
    API_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: ${API_HOSTNAME}" http://127.0.0.1 2>/dev/null || echo "000")
    if [ "$API_STATUS" = "200" ]; then
        echo -e "${GREEN}✓ HTTP ${API_STATUS}${NC}"
    else
        echo -e "${YELLOW}⚠ HTTP ${API_STATUS}${NC}"
    fi

    # Test Frontend
    echo -n "  Frontend (${APP_HOSTNAME}): "
    APP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: ${APP_HOSTNAME}" http://127.0.0.1 2>/dev/null || echo "000")
    if [ "$APP_STATUS" = "200" ]; then
        echo -e "${GREEN}✓ HTTP ${APP_STATUS}${NC}"
    else
        echo -e "${YELLOW}⚠ HTTP ${APP_STATUS}${NC}"
    fi

    # Test Metrics
    echo -n "  Metrics (${API_HOSTNAME}/metrics): "
    METRICS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: ${API_HOSTNAME}" http://127.0.0.1/metrics 2>/dev/null || echo "000")
    if [ "$METRICS_STATUS" = "200" ]; then
        echo -e "${GREEN}✓ HTTP ${METRICS_STATUS}${NC}"
    else
        echo -e "${YELLOW}⚠ HTTP ${METRICS_STATUS}${NC}"
    fi
}

# ============================================================================
# Main
# ============================================================================

main() {
    echo ""
    echo "============================================================"
    echo "  3-Tier Application Build & Deploy"
    echo "============================================================"
    echo ""
    echo "Configuration:"
    echo "  Cluster:   ${CLUSTER_NAME}"
    echo "  Namespace: ${APP_NAMESPACE}"
    echo "  Backend:   ${BACKEND_FULL_IMAGE}"
    echo "  Frontend:  ${FRONTEND_FULL_IMAGE}"
    echo ""

    # Parse arguments
    local build_only=false
    for arg in "$@"; do
        if [ "$arg" == "--build-only" ]; then
            build_only=true
        fi
    done

    build_images
    import_images

    if [ "$build_only" = true ]; then
        echo ""
        echo "============================================================"
        echo -e "  ${GREEN}Build & Import Complete!${NC}"
        echo "============================================================"
        echo "Skiping deployment (--build-only specified)."
        exit 0
    fi

    deploy_app
    verify_deployment

    echo ""
    echo "============================================================"
    echo -e "  ${GREEN}Deployment Complete!${NC}"
    echo "============================================================"
    echo ""
    echo "Access your application:"
    echo "  • Frontend: http://${APP_HOSTNAME}"
    echo "  • API:      http://${API_HOSTNAME}"
    echo "  • Metrics:  http://${API_HOSTNAME}/metrics"
    echo ""
    echo "Add to /etc/hosts if needed:"
    echo "  127.0.0.1 ${APP_HOSTNAME} ${API_HOSTNAME}"
    echo ""
    echo "Useful commands:"
    echo "  kubectl get pods -n ${APP_NAMESPACE}"
    echo "  kubectl logs -l app=backend -n ${APP_NAMESPACE}"
    echo "  kubectl logs -l app=frontend -n ${APP_NAMESPACE}"
    echo ""
}

main "$@"
