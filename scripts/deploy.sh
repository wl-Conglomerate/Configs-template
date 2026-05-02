#!/bin/bash

set -e

REPO_NAME="$1"
SSH_USER="${2:-github_actions}"

if [ -z "$REPO_NAME" ]; then
    echo "Error: REPO_NAME argument is missing."
    exit 1
fi

OUT_DIR="/var/lib/hexrift/$REPO_NAME"
KEYS_DIR="/usr/local/share/hexrift/$REPO_NAME"
TOPOLOGY_FILE="$KEYS_DIR/topology.yaml"

TMP_OUT_DIR=$(mktemp -d)
hexrift --yaml "$TOPOLOGY_FILE" build --all --xray --haproxy --keys-dir "$KEYS_DIR" --out-dir "$TMP_OUT_DIR" || { rm -rf "$TMP_OUT_DIR"; exit 1; }

# Remove node dirs that were not rebuilt (deleted from topology)
for dir in "$OUT_DIR"/*/; do
    [ -d "$dir" ] || continue
    node=$(basename "$dir")
    if [ ! -d "$TMP_OUT_DIR/$node" ]; then
        rm -rf "$dir"
    fi
done

cp -r "$TMP_OUT_DIR/." "$OUT_DIR/"
rm -rf "$TMP_OUT_DIR"

FAILED_FILE=$(mktemp)
trap 'rm -f "$FAILED_FILE"' EXIT

deploy_to_server() {
    local server_path="$1"
    local server
    server=$(basename "$server_path")

    echo "Deploying to $server..."

    if ! scp -q -o StrictHostKeyChecking=accept-new "${server_path}/config.json" "${server_path}/haproxy.cfg" "$SSH_USER@$server:/tmp/"; then
        echo "FAILED: $server (file transfer)"
        echo "$server" >> "$FAILED_FILE"
        return
    fi

    if ! ssh -q -o StrictHostKeyChecking=accept-new "$SSH_USER@$server" \
        "sudo mv /tmp/config.json /usr/local/etc/xray/config.json && \
         sudo mv /tmp/haproxy.cfg /etc/haproxy/haproxy.cfg && \
         sudo systemctl restart xray && \
         sudo systemctl reload haproxy"; then
        echo "FAILED: $server (service restart)"
        echo "$server" >> "$FAILED_FILE"
        return
    fi

    echo "OK: $server"
}

deploy_region() {
    trap - EXIT
    local prefix="$1"
    local is_first=true

    for server_path in "$OUT_DIR"/"$prefix"*/; do
        [ -d "$server_path" ] || continue

        if [ "$is_first" = true ]; then
            is_first=false
        else
            sleep 10
        fi

        deploy_to_server "$server_path"
    done
}

# Find all directories, extract the base name, strip everything from the first uppercase letter onward, and get unique values
unique_prefixes=$(find "$OUT_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sed -E 's/([a-z]+)[A-Z].*/\1/' | sort -u)

for prefix in $unique_prefixes; do
    deploy_region "$prefix" &
done

wait

if [ -s "$FAILED_FILE" ]; then
    echo ""
    echo "The following nodes failed to deploy:"
    while IFS= read -r node; do
        echo "  - $node"
    done < "$FAILED_FILE"
    exit 1
fi

echo "All deployments finished successfully."
