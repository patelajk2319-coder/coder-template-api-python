# shellcheck shell=bash
# Wraps the coder CLI in a detached process session via os.setsid() so it
# cannot open /dev/tty and leak terminal escape sequences into the parent
# shell's input buffer. Source this before any coder invocation.

coder() {
  python3 -c "
import subprocess, os, sys
r = subprocess.run(['coder'] + sys.argv[1:], preexec_fn=os.setsid)
exit(r.returncode)
" "$@"
}

# Coder's LB is internal-only — CODER_URL is a port-forward, not a public
# address. Fail fast with a clear message rather than a cryptic curl/JSON error.
require_coder_reachable() {
  curl -sf --max-time 3 "${CODER_URL}/healthz" &>/dev/null && return 0
  echo "[error] Coder not reachable at ${CODER_URL}" >&2
  echo "[error] Start the port-forward first: task port-forward (in coder-demo-eks)" >&2
  exit 1
}
