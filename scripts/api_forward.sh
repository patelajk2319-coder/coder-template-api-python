#!/usr/bin/env bash
# Forward a workspace's api-python port to localhost, so local tools
# (Postman, curl, a browser) can reach it directly — the app tab only works
# inside the Coder dashboard, proxied through your browser session.

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

WORKSPACE_NAME="${1:?Usage: api_forward.sh <workspace-name> [local-port]}"
LOCAL_PORT="${2:-8000}"

# ── Authenticate ───────────────────────────────────────────────────────────────
TOKEN=$(curl -sf -X POST "${CODER_URL}/api/v2/users/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"${CODER_ADMIN_EMAIL}\",\"password\":\"${CODER_ADMIN_PASSWORD}\"}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['session_token'])")

coder login "${CODER_URL}" --token "${TOKEN}" &>/dev/null

echo "[info] Forwarding localhost:${LOCAL_PORT} -> ${WORKSPACE_NAME}:8000"
echo "[info] Point Postman/curl at http://localhost:${LOCAL_PORT} — Ctrl+C to stop"

# Runs the real binary directly (not the lib/coder.sh wrapper) — that wrapper
# detaches into a new session via os.setsid to stop short-lived commands from
# leaking terminal escapes, but that also stops this long-running, blocking
# command from receiving Ctrl+C, which is exactly how it's meant to be stopped.
command coder port-forward "${WORKSPACE_NAME}" --tcp "${LOCAL_PORT}:8000"
