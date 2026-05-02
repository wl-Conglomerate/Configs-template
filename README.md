# Conglomerate Configs

Configuration repository for a Conglomerate proxy network - a multi-region VPN/proxy infrastructure managed as code.

This is a **GitHub repository template**. Use it as the starting point for your own private configuration repository.

> [!NOTE]
> This template currently works only with a **Bastion/Edge server** and the **[HexRift](https://wlix13.github.io/HexRift/)** CLI tool. See [Requirements](#requirements) before proceeding.

## Requirements

- A **Bastion/Edge server** reachable over SSH - all deployment and update workflows proxy through it using agent forwarding
- **HexRift** CLI available on the Bastion (`uv tool install hexrift`); workflows keep it up to date automatically
- A `github_actions` system user configured on the Bastion and on every proxy node (see below)

### `github_actions` user setup

The `github_actions` user must exist on the Bastion and all proxy nodes with the following in place:

**SSH access** - the user's `authorized_keys` on every node must contain the Bastion's `github_actions` public key (agent forwarding is used, so nodes never need the GitHub Actions key directly).

**Sudoers** - the following `NOPASSWD` entries are required on every node (`/etc/sudoers.d/github_actions`):

```bash
github_actions ALL=(root) NOPASSWD: /bin/systemctl restart xray
github_actions ALL=(root) NOPASSWD: /bin/systemctl restart haproxy
github_actions ALL=(root) NOPASSWD: /bin/systemctl reload haproxy
github_actions ALL=(root) NOPASSWD: /bin/systemctl restart cloudflare-warp
github_actions ALL=(root) NOPASSWD: /usr/sbin/haproxy
github_actions ALL=(root) NOPASSWD: /usr/bin/mv
```

**ACL permissions** - the `acl` package must be installed and the user must have `rwx` access to the config directories:

```bash
setfacl -m u:github_actions:rwx /usr/local/etc/xray/
setfacl -d -m u:github_actions:rwx /usr/local/etc/xray/
setfacl -m u:github_actions:rwx /etc/haproxy/
setfacl -d -m u:github_actions:rwx /etc/haproxy/
```

> [!NOTE]
> The Bastion additionally needs the sudoers entry for `/usr/bin/mv` to move topology files into place.

## Initial Setup

Instead of configuring nodes manually, use the scripts in `scripts/`:

**Prepare the Bastion** (once per repo, run on the Bastion):

```bash
bash scripts/prepare-bastion.sh <repo-name> [admin-user]
```

Creates `/var/lib/hexrift/<repo-name>/` and `/usr/local/share/hexrift/<repo-name>/` with the correct ACLs for `github_actions` and the edge admin user (defaults to `$USER`).

**Prepare proxy nodes** (run from the Bastion whenever you add nodes):

```bash
# One or more nodes as arguments
bash scripts/prepare-node.sh nodeA nodeB

# Or pipe from hexrift to configure all nodes at once
hexrift --yaml topology.yaml nodes --names | bash scripts/prepare-node.sh
```

Idempotently creates the `github_actions` user, writes sudoers, copies the Bastion's authorized key, and sets ACLs on `/usr/local/etc/xray/` and `/etc/haproxy/`.

## Getting Started

**1. Create your private repository from this template**

Create a new empty private repository on GitHub, then mirror the template content into it:

```bash
git clone --bare https://github.com/wlix13/conglomerate-configs-template.git
cd conglomerate-configs-template.git
git push --mirror https://github.com/<your-org>/<your-repo>.git
cd ..
rm -rf conglomerate-configs-template.git
```

Or if you already have the template cloned locally:

```bash
gh repo create <your-org>/<your-repo> --private
git remote add origin git@github.com:<your-org>/<your-repo>.git
git push -u origin main
```

**2. Finish setup**

1. Add `topology.yaml` to the repository root (see HexRift documentation for the format)
2. Configure the required GitHub Actions secrets (see table below)
3. Open a PR with your `topology.yaml` - CI validates it automatically
4. Merge to `main` to trigger deployment

### Secrets

| Secret | Required | Description |
|---|:---:|---|
| `SSH_PRIVATE_KEY` | Yes | Private key for SSH authentication |
| `EDGE_HOST` | Yes | Bastion/Edge server hostname |
| `EDGE_PORT` | Yes | SSH port on the Bastion |
| `EDGE_USER` | Yes | SSH username on the Bastion |
| `DISCORD_WEBHOOK_URL` | | Discord webhook URL for deploy notifications |
| `DISCORD_THREAD_ID` | | Discord thread ID to post notifications into |

## Workflows

| Workflow | Trigger | Description |
|---|---|---|
| **Validate Topology** | PR touching `topology.yaml` | Runs `hexrift validate` and posts a `hexrift show` summary as a PR comment |
| **Deploy** | Push to `main` (changes to `topology.yaml` or `scripts/deploy.sh`), or manual | Builds all node configs on the Bastion, deploys to each node via SCP+SSH |
| **Update Xray** | Weekly (Sunday 02:00 UTC) or manual | Builds latest `xtls/xray-core` from source and rolls it out to all nodes |
| **Update Usque** | Manual only | Builds latest `diniboy1123/usque` from source and rolls it out to all nodes |
| **Sync Labels** | Push to `main` (changes to `.github/labels.yaml`), or manual | Syncs issue labels from `.github/labels.yaml` |

### Deploy

On merge to `main`, the workflow SSHes into the Bastion, copies `topology.yaml` and `deploy.sh`, runs `hexrift build --all`, then deploys each node's `config.json` and `haproxy.cfg` via SCP. Nodes within a region are deployed 10 seconds apart; different regions deploy in parallel. Results are posted to the Actions summary and Discord.

### Auto-updating tools

**Xray** runs every Sunday at 02:00 UTC (and on manual dispatch). It fetches the latest commit SHA from `xtls/xray-core`, builds a stripped binary with aggressive optimizations, and rolls it out to every node, restarting the `xray` service. Binaries are cached by source commit SHA - a rebuild only happens when upstream changes.

**Usque** (Cloudflare WARP client) is manual-dispatch only. Same build and rollout flow as Xray, but deploys to `/usr/local/bin/usque` and restarts the `cloudflare-warp` service. The `cloudflare-warp` systemd service is provisioned by the [NullForge](https://github.com/wlix13/nullforge) project.

Both workflows send a Discord notification on completion regardless of outcome.

## Commit Conventions

Commits in this repo follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>[optional scope]: <description>
```

Allowed types: `feat`, `fix`, `build`, `chore`, `ci`, `docs`, `refactor`, `perf`, `style`, `test`, `revert`.

## License

[MIT](LICENSE)
