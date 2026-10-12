#!/usr/bin/env bash
# Create the platform vault (hypervisor secrets for Ansible) with generated values.
# Lab secrets are separate: helpers/lab-secrets.sh <lab>.
# Usage: ./bootstrap/vault-init.sh
#   Password file: ansible/.vault-pass (gitignored; ansible.cfg points at it; back it up)
#   Secrets:       ansible/inventory/group_vars/all/vault.yml (loaded by every playbook; gitignored)
# Edit secrets later (from ansible/): ansible-vault edit inventory/group_vars/all/vault.yml
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ANSIBLE_DIR="$ROOT/ansible"
PASS_FILE="$ANSIBLE_DIR/.vault-pass"
VAULT="$ANSIBLE_DIR/inventory/group_vars/all/vault.yml"

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

[[ ! -f "$VAULT" ]] || die "$VAULT already exists. Edit it from ansible/ with: ansible-vault edit inventory/group_vars/all/vault.yml"

log "Creating encrypted $VAULT"
mkdir -p "$(dirname "$VAULT")"
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
cat > "$tmp" <<EOF
# Encrypted with ansible-vault. Edit (from ansible/): ansible-vault edit inventory/group_vars/all/vault.yml

# rsync repository (repo.yml, repo-mirror.yml)
vault_rsync_password: $(head -c 24 /dev/urandom | base64 | tr -d '/+=')
EOF
# ansible/ansible.cfg supplies the password file
(cd "$ANSIBLE_DIR" && ansible-vault encrypt --output "$VAULT" "$tmp" >/dev/null)
log "Done. Back up $PASS_FILE: without it the vault cannot be decrypted."
