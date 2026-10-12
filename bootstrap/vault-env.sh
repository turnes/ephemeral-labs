#!/usr/bin/env bash
# Print export lines for Terraform: each key under vault_terraform becomes TF_VAR_<key>.
# Usage: eval "$(./bootstrap/vault-env.sh)"
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# ansible.cfg in the project root provides the vault password file
cd "$ROOT"
ansible-vault view group_vars/all/vault.yml | python3 -c '
import re, shlex, sys, yaml
data = yaml.safe_load(sys.stdin) or {}
for key, value in (data.get("vault_terraform") or {}).items():
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", str(key)):
        sys.exit(f"vault-env.sh: invalid Terraform variable name: {key}")
    print(f"export TF_VAR_{key}={shlex.quote(str(value))}")
'
