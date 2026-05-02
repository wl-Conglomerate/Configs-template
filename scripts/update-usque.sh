#!/bin/bash

set -e

REPO_NAME="$1"
SSH_USER="${2:-github_actions}"

if [ -z "$REPO_NAME" ]; then
    echo "Error: REPO_NAME argument is missing."
    exit 1
fi

TOPOLOGY_FILE="/usr/local/share/hexrift/$REPO_NAME/topology.yaml"

mapfile -t SERVERS < <(hexrift --yaml "$TOPOLOGY_FILE" nodes --names | tr -d '\r')

FAILED_FILE=$(mktemp)
trap 'rm -f "$FAILED_FILE"' EXIT

deploy_to_server() {
    local server="$1"
    echo "==> [$server] updating..."

    if ! scp -q -o StrictHostKeyChecking=accept-new "${DEPLOY_BIN:-/tmp/usque}" "$SSH_USER@$server:/tmp/usque"; then
        echo "FAILED: $server (file transfer)"
        echo "$server" >> "$FAILED_FILE"
        return
    fi

    if ! ssh -q -o StrictHostKeyChecking=accept-new "$SSH_USER@$server" \
        "sudo mv /tmp/usque /usr/local/bin/usque && \
         sudo systemctl restart cloudflare-warp"; then
        echo "FAILED: $server (service restart)"
        echo "$server" >> "$FAILED_FILE"
        return
    fi

    echo "OK: $server"
}

deploy_region() {
    local prefix="$1"; shift
    local servers=("$@")
    local is_first=true

    for server in "${servers[@]}"; do
        [ "$is_first" = true ] && is_first=false || sleep 10
        deploy_to_server "$server"
    done
}

declare -A region_map
for server in "${SERVERS[@]}"; do
    prefix=$(echo "$server" | sed -E 's/([a-z]+)[A-Z].*/\1/')
    region_map[$prefix]="${region_map[$prefix]:-} $server"
done

for prefix in "${!region_map[@]}"; do
    read -ra servers <<< "${region_map[$prefix]}"
    deploy_region "$prefix" "${servers[@]}" &
done

wait

if [ -s "$FAILED_FILE" ]; then
    echo ""
    echo "The following nodes failed:"
    while IFS= read -r node; do
        echo "  - $node"
    done < "$FAILED_FILE"
    exit 1
fi

echo "All servers updated."