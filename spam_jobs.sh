#!/bin/bash
source config.env

URL="http://127.0.0.1/job"
HOST_HEADER="${API_HOSTNAME}"

echo_header() {
    echo -e "\n\033[1;34m$1\033[0m"
}

echo_info() {
    echo -e "\033[1;36m[INFO]\033[0m $1"
}

echo_header "Job Spammer - RabbitMQ Load Generator"
echo_info "Target: $URL (Host: $HOST_HEADER)"
echo_info "Sending 500 jobs..."

if command -v hey &> /dev/null; then
    # -n 500 requests, -c 50 concurrency
    hey -n 500 -c 50 -m POST -host "$HOST_HEADER" "$URL"
else
    echo_info "Using curl (fallback)..."
    for i in {1..500}; do
        curl -s -X POST -H "Host: $HOST_HEADER" "$URL" > /dev/null &
        if (( i % 50 == 0 )); then
            echo -n "."
        fi
    done
    wait
    echo ""
fi

echo_info "Spam completed. Check RabbitMQ Queue backlog."
