#!/bin/bash

# ============================================================================
# 3-Tier Application Build and Deploy Script
# ============================================================================
# Builds Docker images, imports them into k3d, and deploys to Kubernetes
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_NAME="devops-lab"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }
echo_header() { echo -e "\n${CYAN}=== $1 ===${NC}\n"; }

# ============================================================================
# Build Docker Images
# ============================================================================

build_images() {
    echo_header "Building Docker Images"

    # Build Backend
    echo_info "Building backend image..."
    docker build -t lab-backend:v1 "${SCRIPT_DIR}/src/backend/"
    echo_info "Backend image built: lab-backend:v1"

    # Build Frontend
    echo_info "Building frontend image..."
    docker build -t lab-frontend:v1 "${SCRIPT_DIR}/src/frontend/"
    echo_info "Frontend image built: lab-frontend:v1"
}

# ============================================================================
# Import Images into k3d
# ============================================================================

import_images() {
    echo_header "Importing Images into k3d Cluster"

    echo_info "Importing lab-backend:v1..."
    k3d image import lab-backend:v1 -c "${CLUSTER_NAME}"

    echo_info "Importing lab-frontend:v1..."
    k3d image import lab-frontend:v1 -c "${CLUSTER_NAME}"

    echo_info "Images imported successfully!"
}

# ============================================================================
# Deploy Application
# ============================================================================

deploy_app() {
    echo_header "Deploying Application to Kubernetes"

    # Deploy in order: Database -> Backend -> Frontend -> Ingress
    echo_info "Deploying PostgreSQL..."
    kubectl apply -f "${SCRIPT_DIR}/manifests/app/postgres.yaml"

    echo_info "Waiting for PostgreSQL to be ready..."
    kubectl wait --for=condition=available --timeout=120s deployment/postgres

    echo_info "Deploying Backend..."
    kubectl apply -f "${SCRIPT_DIR}/manifests/app/backend.yaml"

    echo_info "Deploying Frontend..."
    kubectl apply -f "${SCRIPT_DIR}/manifests/app/frontend.yaml"

    echo_info "Creating IngressRoutes..."
    kubectl apply -f "${SCRIPT_DIR}/manifests/app/ingress.yaml"

    echo_info "Waiting for all deployments to be ready..."
    kubectl wait --for=condition=available --timeout=120s deployment/backend
    kubectl wait --for=condition=available --timeout=120s deployment/frontend
}

# ============================================================================
# Verify Deployment
# ============================================================================

verify_deployment() {
    echo_header "Verifying Deployment"

    echo_info "Pods status:"
    kubectl get pods -l "app in (postgres,backend,frontend)"

    echo ""
    echo_info "Services:"
    kubectl get svc -l "app in (postgres,backend,frontend)"

    echo ""
    echo_info "IngressRoutes:"
    kubectl get ingressroute

    echo ""
    echo_info "Testing endpoints..."
    sleep 3

    # Test API
    echo -n "  API (api.localhost): "
    API_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: api.localhost" http://127.0.0.1 2>/dev/null || echo "000")
    if [ "$API_STATUS" = "200" ]; then
        echo -e "${GREEN}✓ HTTP ${API_STATUS}${NC}"
    else
        echo -e "${YELLOW}⚠ HTTP ${API_STATUS}${NC}"
    fi

    # Test Frontend
    echo -n "  Frontend (app.localhost): "
    APP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: app.localhost" http://127.0.0.1 2>/dev/null || echo "000")
    if [ "$APP_STATUS" = "200" ]; then
        echo -e "${GREEN}✓ HTTP ${APP_STATUS}${NC}"
    else
        echo -e "${YELLOW}⚠ HTTP ${APP_STATUS}${NC}"
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

    build_images
    import_images
    deploy_app
    verify_deployment

    echo ""
    echo "============================================================"
    echo -e "  ${GREEN}Deployment Complete!${NC}"
    echo "============================================================"
    echo ""
    echo "Access your application:"
    echo "  • Frontend: http://app.localhost"
    echo "  • API:      http://api.localhost"
    echo ""
    echo "Make sure to add these entries to /etc/hosts:"
    echo "  127.0.0.1 app.localhost api.localhost"
    echo ""
    echo "Useful commands:"
    echo "  kubectl get pods              # View all pods"
    echo "  kubectl logs -l app=backend   # View backend logs"
    echo "  kubectl logs -l app=frontend  # View frontend logs"
    echo ""
}

main "$@"
