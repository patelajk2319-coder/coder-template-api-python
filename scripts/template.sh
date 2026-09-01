#!/usr/bin/env bash
# Push the api-python workspace template to the Coder server.

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
: "${TEMPLATE_OWNER:?TEMPLATE_OWNER must be set in .env}"
: "${TEMPLATE_COST_CENTRE:?TEMPLATE_COST_CENTRE must be set in .env}"
: "${TEMPLATE_TEAM:?TEMPLATE_TEAM must be set in .env}"
: "${TEMPLATE_ENV:?TEMPLATE_ENV must be set in .env}"
: "${TEMPLATE_DEFAULT_TTL:?TEMPLATE_DEFAULT_TTL must be set in .env}"
: "${TEMPLATE_ACTIVITY_BUMP:?TEMPLATE_ACTIVITY_BUMP must be set in .env}"

require_coder_reachable

TEMPLATE_NAME="api-python-workspace"

VERSION="$(cat "${ROOT_DIR}/VERSION")"

# Routes builds to a specific external provisioner (e.g. a team-owned
# cluster) instead of the control plane's built-in ones. Optional — leave
# PROVISIONER_TAG unset in .env to keep using the built-in provisioners.
PROVISIONER_TAG_FLAGS=()
if [[ -n "${PROVISIONER_TAG:-}" ]]; then
  PROVISIONER_TAG_FLAGS=(--provisioner-tag "${PROVISIONER_TAG}")
fi

GOVERNANCE_DESC="owner: ${TEMPLATE_OWNER} | cost-centre: ${TEMPLATE_COST_CENTRE} | team: ${TEMPLATE_TEAM} | env: ${TEMPLATE_ENV}"

# ── Authenticate ───────────────────────────────────────────────────────────────
coder_login

echo "[----] Pushing ${TEMPLATE_NAME}@${VERSION} to ${CODER_URL}..."
coder templates push "${TEMPLATE_NAME}" \
  --directory "${ROOT_DIR}/templates/${TEMPLATE_NAME}" \
  --name "${VERSION}" \
  --yes \
  "${PROVISIONER_TAG_FLAGS[@]}"

TEMPLATE_ID=$(curl -sf \
  -H "Coder-Session-Token: ${TOKEN}" \
  "${CODER_URL}/api/v2/organizations/default/templates/${TEMPLATE_NAME}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

curl -sf -X PATCH \
  -H "Coder-Session-Token: ${TOKEN}" \
  -H "Content-Type: application/json" \
  "${CODER_URL}/api/v2/templates/${TEMPLATE_ID}" \
  -d "{
    \"display_name\": \"API Python Workspace\",
    \"description\": \"${GOVERNANCE_DESC}\"
  }" > /dev/null

# Idle workspaces auto-stop after TEMPLATE_DEFAULT_TTL. activity-bump must be
# set explicitly — it defaults to 0 (off), which would stop active sessions too.
coder templates edit "${TEMPLATE_NAME}" \
  --default-ttl="${TEMPLATE_DEFAULT_TTL}" \
  --activity-bump="${TEMPLATE_ACTIVITY_BUMP}" \
  --yes

echo "[info] ${TEMPLATE_NAME} — live"
echo ""
echo "[info] version:     ${VERSION}"
echo "[info] owner:       ${TEMPLATE_OWNER}"
echo "[info] cost-centre: ${TEMPLATE_COST_CENTRE}"
echo "[info] team:        ${TEMPLATE_TEAM}"
echo "[info] env:         ${TEMPLATE_ENV}"
