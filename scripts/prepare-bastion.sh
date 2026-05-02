#!/usr/bin/env bash

set -euo pipefail

# Usage: prepare-bastion.sh <repo-name> [admin-user]
#
# Creates the hexrift directory tree for <repo-name> on the Bastion and grants
# ACLs to github_actions and <admin-user> (defaults to the current user).
#
# Run once per repo after cloning the template.

REPO_NAME="${1:-}"
ADMIN_USER="${2:-$USER}"

if [[ -z "$REPO_NAME" ]]; then
    echo "Usage: $0 <repo-name> [admin-user]" >&2
    exit 1
fi

VAR_DIR="/var/lib/hexrift/$REPO_NAME"
SHARE_DIR="/usr/local/share/hexrift/$REPO_NAME"

echo "==> Creating directories..."
sudo mkdir -p "$VAR_DIR" "$SHARE_DIR"

if ! command -v setfacl &>/dev/null; then
    echo "==> Installing acl..."
    sudo apt-get update -qq && sudo apt-get install -y acl
fi

echo "==> Setting ACLs on $VAR_DIR..."
sudo setfacl -m u:github_actions:rwx "$VAR_DIR"
sudo setfacl -d -m u:github_actions:rwx "$VAR_DIR"
sudo setfacl -m u:"$ADMIN_USER":rwx "$VAR_DIR"
sudo setfacl -d -m u:"$ADMIN_USER":rwx "$VAR_DIR"

echo "==> Setting ACLs on $SHARE_DIR..."
sudo setfacl -m u:github_actions:rwx "$SHARE_DIR"
sudo setfacl -d -m u:github_actions:rwx "$SHARE_DIR"
sudo setfacl -m u:"$ADMIN_USER":rwx "$SHARE_DIR"
sudo setfacl -d -m u:"$ADMIN_USER":rwx "$SHARE_DIR"

echo "==> Done. Bastion is ready for repo '$REPO_NAME'."
