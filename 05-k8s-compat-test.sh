#!/bin/bash
source config.env

echo_header "Kubernetes Version Compatibility Testing"

# Versions mapping
declare -A VERSIONS
VERSIONS["1.22"]="rancher/k3s:v1.22.17-k3s1"
VERSIONS["1.25"]="rancher/k3s:v1.25.16-k3s4"
VERSIONS["1.27"]="rancher/k3s:v1.27.16-k3s1"
VERSIONS["1.28"]="rancher/k3s:v1.28.15-k3s1"
VERSIONS["1.29"]="rancher/k3s:v1.29.10-k3s1"
VERSIONS["1.30"]="rancher/k3s:v1.30.6-k3s1"
VERSIONS["1.35"]="rancher/k3s:v1.35.0-k3s1"

# Determine k3d binary
K3D_BIN="k3d"
if [ -f "k3d" ]; then
    K3D_BIN="./k3d"
fi

run_test() {
    local ver=$1
    local image=${VERSIONS[$ver]}
    
    if [ -z "$image" ]; then
        echo_error "Unknown version: $ver"
        return
    fi
    
    echo_header "Testing K8s $ver ($image)"
    
    # Clean up first
    echo_info "Cleaning up existing cluster..."
    $K3D_BIN cluster delete $CLUSTER_NAME 2>/dev/null
    
    # Run setup
    export K3S_IMAGE=$image
    ./01-setup-cluster.sh
    if [ $? -ne 0 ]; then
        echo_error "Cluster creation failed for $ver"
        return
    fi
    
    # Run tools
    ./02-install-tools.sh
    
    # Deploy app
    ./03-deploy-app.sh
    
    echo_info "✓ Test for $ver completed"
}

if [ "$1" == "all" ]; then
    for ver in "${!VERSIONS[@]}"; do
        run_test $ver
    done
elif [ -n "$1" ]; then
    run_test $1
else
    echo "Usage: $0 [version] or 'all'"
    echo "Available versions: ${!VERSIONS[@]}"
fi
