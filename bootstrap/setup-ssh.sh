#!/usr/bin/env bash
# Create the ephemeral-labs SSH key, write a ~/.ssh config entry per host and copy the key to each host.
# Usage: ./setup-ssh.sh [hosts-file]   (default: ssh-hosts next to this script)
# Hosts file format, one per line:  name  address  user  [port]
# Run as your normal user, not root. Targets need openssh-server and password login for the first copy.
set -euo pipefail

HOSTS_FILE="${1:-$(dirname "$0")/ssh-hosts}"
KEY_DIR="$HOME/.ssh/ephemeral-labs"
KEY="$KEY_DIR/id_ed25519"
INCLUDE_LINE="Include ~/.ssh/ephemeral-labs/*.conf"

log()  { echo -e "\e[1;32m==>\e[0m $*"; }
warn() { echo -e "\e[1;33m!!\e[0m $*" >&2; }
die()  { echo -e "\e[1;31mxx\e[0m $*" >&2; exit 1; }

[[ $EUID -ne 0 ]] || die "Run as your normal user, not root."
[[ -f "$HOSTS_FILE" ]] || die "Hosts file not found: $HOSTS_FILE (copy ssh-hosts.example to ssh-hosts)."

mkdir -p "$KEY_DIR"
chmod 700 "$HOME/.ssh" "$KEY_DIR"

if [[ -f "$KEY" ]]; then
    log "Using existing key $KEY"
else
    log "Creating key $KEY"
    ssh-keygen -t ed25519 -N "" -C "ephemeral-labs@$(hostname)" -f "$KEY" -q
fi

# Include must come before any Host block in ~/.ssh/config to apply globally
touch "$HOME/.ssh/config"
chmod 600 "$HOME/.ssh/config"
if ! grep -qxF "$INCLUDE_LINE" "$HOME/.ssh/config"; then
    log "Adding Include to ~/.ssh/config"
    { printf '%s\n\n' "$INCLUDE_LINE"; cat "$HOME/.ssh/config"; } > "$HOME/.ssh/config.tmp"
    mv "$HOME/.ssh/config.tmp" "$HOME/.ssh/config"
    chmod 600 "$HOME/.ssh/config"
fi

failed=()
# Read hosts on fd 3 so ssh-copy-id can still prompt for passwords on stdin
while read -r name address user port <&3; do
    [[ -z "$name" || "$name" == \#* ]] && continue
    [[ -n "$address" && -n "$user" ]] || { warn "Skipping malformed line for '$name'"; continue; }
    port="${port:-22}"

    log "$name ($user@$address:$port)"
    cat > "$KEY_DIR/$name.conf" <<EOF
Host $name
    HostName $address
    User $user
    Port $port
    IdentityFile $KEY
    IdentitiesOnly yes
EOF

    if ssh -o BatchMode=yes -o ConnectTimeout=5 "$name" true </dev/null 2>/dev/null; then
        echo "   key already installed"
        continue
    fi
    if ssh-copy-id -i "$KEY.pub" -o StrictHostKeyChecking=accept-new -p "$port" "$user@$address" \
        && ssh -o BatchMode=yes -o ConnectTimeout=5 "$name" true </dev/null; then
        echo "   ok"
    else
        warn "Could not set up $name"
        failed+=("$name")
    fi
done 3< "$HOSTS_FILE"

(( ${#failed[@]} == 0 )) || die "Failed hosts: ${failed[*]}"
log "Done. Connect with: ssh <name>"
