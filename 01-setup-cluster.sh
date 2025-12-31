#!/bin/bash

# ============================================================================
# K3d DevOps Lab Cluster Setup Script
# ============================================================================
# This script provisions a k3d Kubernetes cluster with:
# - 1 Server node (Master)
# - 3 Agent nodes (Workers)
# - Port mappings: 80, 443, 8080
# - Default K3s Traefik ingress controller enabled
# ============================================================================

set -e

CLUSTER_NAME="devops-lab"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ============================================================================
# Step 1: Check Prerequisites
# ============================================================================

check_prerequisites() {
    echo_info "Checking prerequisites..."

    # Check k3d
    if ! command -v k3d &> /dev/null; then
        echo_error "k3d is not installed."
        echo_info "To install k3d, run one of these commands:"
        echo ""
        echo "  # Using curl (recommended)"
        echo "  curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash"
        echo ""
        echo "  # Using wget"
        echo "  wget -q -O - https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash"
        echo ""
        echo "  # Using Homebrew (macOS/Linux)"
        echo "  brew install k3d"
        echo ""
        exit 1
    else
        echo_info "k3d is installed: $(k3d version | head -1)"
    fi

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        echo_error "kubectl is not installed."
        echo_info "To install kubectl, run one of these commands:"
        echo ""
        echo "  # Linux (x86_64)"
        echo "  curl -LO \"https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl\""
        echo "  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl"
        echo ""
        echo "  # macOS (Intel)"
        echo "  curl -LO \"https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/amd64/kubectl\""
        echo "  chmod +x ./kubectl && sudo mv ./kubectl /usr/local/bin/kubectl"
        echo ""
        echo "  # Using Homebrew (macOS/Linux)"
        echo "  brew install kubectl"
        echo ""
        exit 1
    else
        echo_info "kubectl is installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client | head -1)"
    fi

    # Check Docker
    if ! command -v docker &> /dev/null; then
        echo_error "Docker is not installed or not running. k3d requires Docker."
        exit 1
    else
        if ! docker info &> /dev/null; then
            echo_error "Docker is installed but not running. Please start Docker."
            exit 1
        fi
        echo_info "Docker is running"
    fi
}

# ============================================================================
# Step 2: Create K3d Cluster
# ============================================================================

create_cluster() {
    echo_info "Creating k3d cluster '${CLUSTER_NAME}'..."

    # Check if cluster already exists
    if k3d cluster list | grep -q "${CLUSTER_NAME}"; then
        echo_warn "Cluster '${CLUSTER_NAME}' already exists."
        read -p "Do you want to delete and recreate it? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo_info "Deleting existing cluster..."
            k3d cluster delete "${CLUSTER_NAME}"
        else
            echo_info "Keeping existing cluster. Skipping creation."
            return 0
        fi
    fi

    # Create the cluster with specified configuration
    # - 1 Server (master) node
    # - 3 Agent (worker) nodes
    # - Port mappings for loadbalancer
    # - Default Traefik is enabled (no --k3s-arg to disable it)
    k3d cluster create "${CLUSTER_NAME}" \
        --servers 1 \
        --agents 3 \
        --port "80:80@loadbalancer" \
        --port "443:443@loadbalancer" \
        --port "8080:8080@loadbalancer" \
        --wait

    echo_info "Cluster '${CLUSTER_NAME}' created successfully!"
}

# ============================================================================
# Step 3: Configure Kubeconfig
# ============================================================================

configure_kubeconfig() {
    echo_info "Configuring kubeconfig..."

    # k3d automatically merges kubeconfig to default location
    # but we can explicitly do it
    k3d kubeconfig merge "${CLUSTER_NAME}" --kubeconfig-merge-default --kubeconfig-switch-context

    echo_info "Kubeconfig merged and context switched to k3d-${CLUSTER_NAME}"
}

# ============================================================================
# Step 4: Verify Cluster
# ============================================================================

verify_cluster() {
    echo_info "Verifying cluster connectivity..."

    # Wait for nodes to be ready
    echo_info "Waiting for all nodes to be Ready..."
    local max_retries=30
    local retry=0

    while [ $retry -lt $max_retries ]; do
        ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || echo "0")
        if [ "$ready_nodes" -eq 4 ]; then
            break
        fi
        echo_info "Waiting for nodes... ($ready_nodes/4 ready)"
        sleep 5
        ((retry++))
    done

    if [ "$ready_nodes" -ne 4 ]; then
        echo_error "Not all nodes are ready after waiting. Please check cluster status."
        kubectl get nodes
        exit 1
    fi

    echo_info "All 4 nodes are Ready!"
    echo ""
    kubectl get nodes -o wide
    echo ""

    # Wait for Traefik to be ready
    echo_info "Waiting for Traefik ingress controller to be ready..."
    kubectl wait --for=condition=available --timeout=120s deployment/traefik -n kube-system 2>/dev/null || {
        echo_warn "Traefik deployment not found or not ready yet. Waiting for pods..."
        sleep 10
    }

    echo_info "Cluster components:"
    kubectl get pods -n kube-system
}

# ============================================================================
# Main
# ============================================================================

main() {
    echo ""
    echo "============================================================"
    echo "  K3d DevOps Lab Cluster Setup"
    echo "============================================================"
    echo ""

    check_prerequisites
    create_cluster
    configure_kubeconfig
    verify_cluster

    echo ""
    echo "============================================================"
    echo -e "  ${GREEN}Setup Complete!${NC}"
    echo "============================================================"
    echo ""
    echo "Cluster Name: ${CLUSTER_NAME}"
    echo "Nodes: 1 server + 3 agents = 4 total"
    echo ""
    echo "Port Mappings:"
    echo "  - localhost:80   -> loadbalancer:80"
    echo "  - localhost:443  -> loadbalancer:443"
    echo "  - localhost:8080 -> loadbalancer:8080"
    echo ""
    echo "Next steps:"
    echo "  1. Verify Traefik: curl localhost (should return 404)"
    echo "  2. Access Traefik dashboard (if enabled)"
    echo "  3. Deploy your applications!"
    echo ""
}

main "$@"
