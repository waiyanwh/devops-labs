#!/bin/bash
source config.env

echo_header "KEDA Load Test - Event Driven Scaling"

API_URL="http://${API_HOSTNAME}/api/hello"

echo_info "Target: $API_URL"
echo_info "Current Replicas:"
kubectl get deployments -n ${APP_NAMESPACE} backend

# Check for k6 or hey or siege, else fallback to curl
if command -v hey &> /dev/null; then
    echo_info "Using 'hey' for load generation..."
    # Use 127.0.0.1 to avoid DNS resolution issues with api.localhost
    CMD="hey -z 120s -q 20 -c 5 -host ${API_HOSTNAME} http://127.0.0.1/api/hello"
else
    echo_info "Using 'curl' loop (fallback)..."
    echo_warn "Install 'hey' or 'k6' for better results."
    CMD="while true; do curl -s -H 'Host: ${API_HOSTNAME}' http://127.0.0.1/api/hello > /dev/null; done"
fi

echo_info "Starting load generation..."
echo_info "Keep this running. Open another terminal to watch scaling:"
echo "  kubectl get hpa -n ${APP_NAMESPACE} -w"
echo ""

# Run in background
eval "$CMD" &
PID=$!

echo_info "Load generator PID: $PID"
echo_info "Generating load for 60 seconds..."

# Monitor loop
for i in {1..24}; do
    kubectl get hpa keda-hpa-backend-scaler -n ${APP_NAMESPACE}
    kubectl get pods -n ${APP_NAMESPACE} -l app=backend
    sleep 5
done

kill $PID
echo_info "Load test stopped."
kubectl get deployments -n ${APP_NAMESPACE} backend
