#!/usr/bin/env bash
# Provision a developer workspace from the api-python-workspace template.
# The workspace is pre-configured with the IDE, tooling, Docker-in-Docker
# sidecar, and repo — zero setup for the developer.
# Requires: task init in coder-demo-eks must have been run first.

set -euo pipefail

export NO_COLOR=1
export TERM=dumb

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
: "${WORKSPACE_REPO:?WORKSPACE_REPO must be set in .env}"

require_coder_reachable

WORKSPACE_NAME="${1:?Usage: workspace.sh <workspace-name>}"

# ── Authenticate ───────────────────────────────────────────────────────────────
TOKEN=$(curl -sf -X POST "${CODER_URL}/api/v2/users/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"${CODER_ADMIN_EMAIL}\",\"password\":\"${CODER_ADMIN_PASSWORD}\"}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['session_token'])")

coder login "${CODER_URL}" --token "${TOKEN}" &>/dev/null
echo "[info] Authenticated as ${CODER_ADMIN_EMAIL}"

# ── Provision workspace ────────────────────────────────────────────────────────
echo "[----] Provisioning workspace '${WORKSPACE_NAME}'..."
echo "[info] Template: api-python-workspace"
echo ""

coder create "${WORKSPACE_NAME}" \
  --template api-python-workspace \
  --parameter instance_size=medium \
  --parameter repo_url="${WORKSPACE_REPO}" \
  --yes
