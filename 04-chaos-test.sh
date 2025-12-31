#!/bin/bash
source config.env

echo_header "Chaos Monkey Testing"

# Function to check recovery
check_recovery() {
    local deployment=$1
    local name=$2
    echo_info "Waiting for $name to recover..."
    kubectl rollout status deployment/$deployment -n $APP_NAMESPACE --timeout=60s
    if [ $? -eq 0 ]; then
        echo_info "✓ $name recovered"
    else
        echo_error "✗ $name failed to recover"
    fi
}

# Test 1: Pod Deletion
echo_header "Test 1: Pod Deletion Resilience"
POD=$(kubectl get pod -n $APP_NAMESPACE -l app=backend -o jsonpath="{.items[0].metadata.name}")
echo_info "Deleting pod: $POD"
kubectl delete pod $POD -n $APP_NAMESPACE --grace-period=0 --force
check_recovery "backend" "Backend"

# Test 2: DB Connection Recovery
echo_header "Test 2: Database Connection Recovery"
POD=$(kubectl get pod -n $APP_NAMESPACE -l app=postgres -o jsonpath="{.items[0].metadata.name}")
echo_info "Deleting PostgreSQL pod..."
kubectl delete pod $POD -n $APP_NAMESPACE --grace-period=0 --force
check_recovery "postgres" "PostgreSQL"
echo_warn "Note: Data loss is expected with ephemeral storage. Backend might need restart to reconnect if logic isn't robust."

# Test 3: Rolling Update
echo_header "Test 3: Rolling Update"
echo_info "Triggering rolling update..."
kubectl rollout restart deployment/backend -n $APP_NAMESPACE
check_recovery "backend" "Backend Rolling Update"

echo_header "Chaos Testing Complete"
