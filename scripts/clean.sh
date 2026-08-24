#!/usr/bin/env bash
# Delete all Coder workspaces and templates, resetting Coder to a clean state.
# The cluster and Coder itself are left running — use task nuke in coder-demo-eks for that.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=scripts/lib/coder.sh
source "${SCRIPT_DIR}/lib/coder.sh"

if [[ ! -f "${ROOT_DIR}/.env" ]]; then
  echo "[error] .env not found — copy .env.example to .env and fill in values" >&2
  exit 1
fi
set -a
# shellcheck source=/dev/null
source "${ROOT_DIR}/.env"
set +a

: "${CODER_URL:?CODER_URL must be set in .env}"
: "${CODER_ADMIN_EMAIL:?CODER_ADMIN_EMAIL must be set in .env}"
: "${CODER_ADMIN_PASSWORD:?CODER_ADMIN_PASSWORD must be set in .env}"

require_coder_reachable

# ── Authenticate ───────────────────────────────────────────────────────────────
TOKEN=$(curl -sf -X POST "${CODER_URL}/api/v2/users/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"${CODER_ADMIN_EMAIL}\",\"password\":\"${CODER_ADMIN_PASSWORD}\"}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['session_token'])")

coder login "${CODER_URL}" --token "${TOKEN}" &>/dev/null
echo "[info] Authenticated as ${CODER_ADMIN_EMAIL}"

# ── Delete all workspaces ──────────────────────────────────────────────────────
WORKSPACES=$(coder ls --output json 2>/dev/null \
  | python3 -c "import sys,json; [print(w['owner_name']+'/'+w['name']) for w in json.load(sys.stdin)]" \
  2>/dev/null || true)

if [[ -z "${WORKSPACES}" ]]; then
  echo "[info] No workspaces to delete"
else
  echo "[----] Deleting workspaces..."
  while IFS= read -r ws; do
    coder delete "${ws}" --yes &
  done <<< "${WORKSPACES}"
  wait
  echo "[info] All workspaces deleted"
fi

# ── Delete all templates ───────────────────────────────────────────────────────
TEMPLATES=$(coder templates ls --output json 2>/dev/null \
  | python3 -c "import sys,json; [print(t['name']) for t in json.load(sys.stdin)]" \
  2>/dev/null || true)

if [[ -z "${TEMPLATES}" ]]; then
  echo "[info] No templates to delete"
else
  echo "[----] Deleting templates..."
  while IFS= read -r tmpl; do
    coder templates delete "${tmpl}" --yes 2>&1 | grep -v "^$" || true
  done <<< "${TEMPLATES}"
  echo "[info] All templates deleted"
fi

echo ""
echo "[info] Coder is clean — run: task up"
