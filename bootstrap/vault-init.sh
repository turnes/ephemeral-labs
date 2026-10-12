#!/usr/bin/env bash
# Create the ansible-vault password file and the encrypted secrets file with generated values.
# Usage: ./bootstrap/vault-init.sh
#   Password file: .vault-pass in the project root (gitignored; ansible.cfg points at it; back it up)
#   Secrets:       group_vars/all/vault.yml (loaded by every playbook; gitignored)
# Edit secrets later with: ansible-vault edit group_vars/all/vault.yml
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS_FILE="$ROOT/.vault-pass"
VAULT="$ROOT/group_vars/all/vault.yml"

log()  { echo -e "\e[1;32m==>\e[0m $*"; }
die()  { echo -e "\e[1;31mxx\e[0m $*" >&2; exit 1; }

command -v ansible-vault >/dev/null || die "ansible-vault not found (sudo apt install -y ansible-core)."
umask 077

if [[ -f "$PASS_FILE" ]]; then
    log "Using existing vault password $PASS_FILE"
else
    log "Creating vault password $PASS_FILE"
    head -c 32 /dev/urandom | base64 > "$PASS_FILE"
fi

[[ ! -f "$VAULT" ]] || die "$VAULT already exists. Edit it with: ansible-vault edit group_vars/all/vault.yml"

log "Creating encrypted $VAULT"
mkdir -p "$(dirname "$VAULT")"
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
cat > "$tmp" <<EOF
# Encrypted with ansible-vault. Edit: ansible-vault edit group_vars/all/vault.yml

# rsync repository (repo.yml, repo-mirror.yml)
vault_rsync_password: $(head -c 24 /dev/urandom | base64 | tr -d '/+=')

# Exported as TF_VAR_<key> by: eval "\$(./bootstrap/vault-env.sh)"
vault_terraform: {}
EOF
# ansible.cfg in the project root supplies the password file
(cd "$ROOT" && ansible-vault encrypt --output "$VAULT" "$tmp" >/dev/null)
log "Done. Back up $PASS_FILE: without it the vault cannot be decrypted."
