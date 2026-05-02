#!/usr/bin/env bash

set -euo pipefail

# Accept nodes as positional args or from stdin
if [[ $# -gt 0 ]]; then
    REMOTE_SERVERS=("$@")
elif [[ ! -t 0 ]]; then
    mapfile -t REMOTE_SERVERS
else
    echo "Usage: $0 [node...] OR: hexrift nodes --names | $0" >&2
    exit 1
fi

ensure_user_local() {
    if ! id -u github_actions &>/dev/null; then
        sudo adduser --system --group --home /home/github_actions --shell /bin/bash github_actions
    fi
    sudo mkdir -p /home/github_actions/.ssh
    sudo chmod 700 /home/github_actions/.ssh
    sudo chown -R github_actions:github_actions /home/github_actions/.ssh
    if [[ -f /home/github_actions/.ssh/authorized_keys ]]; then
        sudo chmod 600 /home/github_actions/.ssh/authorized_keys
        sudo chown github_actions:github_actions /home/github_actions/.ssh/authorized_keys
    fi
    sudo touch /home/github_actions/.hushlogin
    sudo chown github_actions:github_actions /home/github_actions/.hushlogin
}

write_sudoers_local() {
    cat <<'EOF' | sudo tee /etc/sudoers.d/github_actions > /dev/null
# Allow github_actions to manage Xray and HAProxy only
github_actions ALL=(root) NOPASSWD: /bin/systemctl restart xray
github_actions ALL=(root) NOPASSWD: /bin/systemctl status xray
github_actions ALL=(root) NOPASSWD: /bin/systemctl is-active xray
github_actions ALL=(root) NOPASSWD: /bin/systemctl restart haproxy
github_actions ALL=(root) NOPASSWD: /bin/systemctl reload haproxy
github_actions ALL=(root) NOPASSWD: /bin/systemctl status haproxy
github_actions ALL=(root) NOPASSWD: /bin/systemctl is-active haproxy
github_actions ALL=(root) NOPASSWD: /bin/systemctl restart cloudflare-warp
github_actions ALL=(root) NOPASSWD: /usr/sbin/haproxy
github_actions ALL=(root) NOPASSWD: /usr/bin/mv
EOF
    sudo chmod 440 /etc/sudoers.d/github_actions
}

setup_remote() {
    local server="$1"
    echo "==> [$server] configuring..."

    # Create user (idempotent)
    ssh "$server" 'id -u github_actions &>/dev/null \
        || sudo adduser --system --group --home /home/github_actions --shell /bin/bash github_actions'

    # .ssh directory
    ssh "$server" 'sudo mkdir -p /home/github_actions/.ssh \
        && sudo chmod 700 /home/github_actions/.ssh \
        && sudo chown -R github_actions:github_actions /home/github_actions/.ssh'

    # authorized_keys — stream from bastion
    sudo cat /home/github_actions/.ssh/authorized_keys \
        | ssh "$server" 'sudo tee /home/github_actions/.ssh/authorized_keys > /dev/null \
            && sudo chmod 600 /home/github_actions/.ssh/authorized_keys \
            && sudo chown github_actions:github_actions /home/github_actions/.ssh/authorized_keys'

    # sudoers
    ssh "$server" 'cat | sudo tee /etc/sudoers.d/github_actions > /dev/null \
            && sudo chmod 440 /etc/sudoers.d/github_actions' <<'SUDOEOF'
# Allow github_actions to manage Xray and HAProxy only
github_actions ALL=(root) NOPASSWD: /bin/systemctl restart xray
github_actions ALL=(root) NOPASSWD: /bin/systemctl status xray
github_actions ALL=(root) NOPASSWD: /bin/systemctl is-active xray
github_actions ALL=(root) NOPASSWD: /bin/systemctl restart haproxy
github_actions ALL=(root) NOPASSWD: /bin/systemctl reload haproxy
github_actions ALL=(root) NOPASSWD: /bin/systemctl status haproxy
github_actions ALL=(root) NOPASSWD: /bin/systemctl is-active haproxy
github_actions ALL=(root) NOPASSWD: /bin/systemctl restart cloudflare-warp
github_actions ALL=(root) NOPASSWD: /usr/sbin/haproxy
github_actions ALL=(root) NOPASSWD: /usr/bin/mv
SUDOEOF

    # .hushlogin
    ssh "$server" 'sudo touch /home/github_actions/.hushlogin \
        && sudo chown github_actions:github_actions /home/github_actions/.hushlogin'

    # ACL — directory defaults cover newly created config files
    ssh "$server" 'sudo apt-get update -qq && sudo apt-get install -y acl \
        && sudo setfacl -m u:github_actions:rwx /usr/local/etc/xray/ \
        && sudo setfacl -d -m u:github_actions:rwx /usr/local/etc/xray/ \
        && sudo setfacl -m u:github_actions:rwx /etc/haproxy/ \
        && sudo setfacl -d -m u:github_actions:rwx /etc/haproxy/'

    echo "==> [$server] done"
}

echo "==> [bastion] configuring..."
ensure_user_local
write_sudoers_local
echo "==> [bastion] done"

pids=()
for server in "${REMOTE_SERVERS[@]}"; do
    setup_remote "$server" &
    pids+=($!)
done

exit_code=0
for pid in "${pids[@]}"; do
    wait "$pid" || exit_code=$?
done

if [[ $exit_code -ne 0 ]]; then
    echo "ERROR: one or more remote servers failed (exit code $exit_code)" >&2
    exit $exit_code
fi

echo "==> All servers configured."
