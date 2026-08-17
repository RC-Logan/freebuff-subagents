#!/usr/bin/env bash
# Bootstrap: install OpenHands, wire the LLM provider, ping the API.
# Idempotent — safe to re-run.
#
# Usage: ./bin/install.sh
# Reads: .env (copy from .env.example) or the current environment.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

# ---- load .env if present (env vars win over the file; see lib/env.sh) -----
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/env.sh"
load_env

# ---- preconditions ---------------------------------------------------------
# Prefer NVIDIA defaults; fall back to the text provider if configured.
API_KEY="${NVIDIA_API_KEY:-${TEXT_API_KEY:-}}"
: "${API_KEY:?No API key found. Set NVIDIA_API_KEY or TEXT_API_KEY (see .env.example)}"
NVIDIA_API_KEY="$API_KEY"
DEFAULT_MODEL="${DEFAULT_MODEL:-${TEXT_MODEL:-z-ai/glm-5.2}}"
BASE_URL="${BASE_URL:-https://integrate.api.nvidia.com/v1}"
RUNTIME="${RUNTIME:-docker}"
case "$RUNTIME" in
  docker|remote) ;;
  process)
    echo "WARNING: RUNTIME=process = NO container isolation (agent commands run" >&2
    echo "         directly on this machine). delegate.sh will refuse to run unless" >&2
    echo "         ALLOW_PROCESS_SANDBOX=1 is set." >&2
    ;;
  *)
    echo "ERROR: unknown RUNTIME '$RUNTIME' (expected docker | process | remote)" >&2
    exit 1
    ;;
esac
if [[ "$RUNTIME" == "docker" ]] \
  && { ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; }; then
  echo
  echo "WARNING: RUNTIME=docker but Docker is not available (missing or daemon down)." >&2
  echo "         Delegations will FAIL until Docker runs. Install e.g.:" >&2
  echo "           brew install --cask orbstack   # or colima, or Docker Desktop" >&2
  echo "         (Install continues; openhands and config will be set up anyway.)" >&2
fi
MAX_ITERATIONS="${MAX_ITERATIONS:-25}"

echo "==> NIM model:  ${DEFAULT_MODEL}"
echo "==> Base URL:   ${BASE_URL}"
echo "==> Sandbox:    ${RUNTIME}"

# ---- uv --------------------------------------------------------------------
if ! command -v uv >/dev/null 2>&1; then
  echo "==> uv not found — installing via the official astral installer"
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi
command -v uv >/dev/null 2>&1 || { echo "ERROR: uv unavailable after install" >&2; exit 1; }

# ---- openhands --------------------------------------------------------------
export PATH="$HOME/.local/bin:$PATH"
if [[ -n "${OPENHANDS_VERSION:-}" ]]; then
  echo "==> Installing openhands-ai==${OPENHANDS_VERSION}"
  uv tool install "openhands-ai==${OPENHANDS_VERSION}"
else
  echo "==> Installing openhands-ai (latest)"
  uv tool install openhands-ai
fi
command -v openhands >/dev/null 2>&1 || { echo "ERROR: openhands not on PATH after install" >&2; exit 1; }

# ---- detect config scheme (V1 agent_settings.json vs V0 config.toml) -------
if openhands --help 2>&1 | grep -q -- '--override-with-envs'; then
  SCHEME="v1"
  echo "==> Detected V1 CLI — writing ~/.openhands/agent_settings.json"
  mkdir -p "$HOME/.openhands"
  cat > "$HOME/.openhands/agent_settings.json" <<EOF
{
  "llm": {
    "model": "openai/${DEFAULT_MODEL}",
    "api_key": "${NVIDIA_API_KEY}",
    "base_url": "${BASE_URL}",
    "temperature": 0.1,
    "max_output_tokens": 4096,
    "num_retries": 4
  },
  "agent": {
    "max_iterations": ${MAX_ITERATIONS}
  }
}
EOF
  echo "    wrote $HOME/.openhands/agent_settings.json"
else
  SCHEME="v0"
  echo "==> Detected V0 CLI — writing ~/.openhands/config.toml"
  mkdir -p "$HOME/.openhands"
  cat > "$HOME/.openhands/config.toml" <<EOF
[llm]
# 'openai/' prefix tells LiteLLM to use OpenAI-compatible routing
model = "openai/${DEFAULT_MODEL}"
base_url = "${BASE_URL}"
api_key = "${NVIDIA_API_KEY}"
temperature = 0.1
max_output_tokens = 4096

[core]
# Safety bounds for the 40 RPM NIM budget
max_iterations = ${MAX_ITERATIONS}
runtime = "${RUNTIME}"
EOF
  echo "    wrote $HOME/.openhands/config.toml"
fi
echo "    scheme: ${SCHEME} (delegate.sh will match this)"

# ---- Freebuff skill: removed (MCP route; fallback in git history) ----------
# The skill was intentionally removed from the tree (DECISIONS.md #16): the
# integrated Freebuff path is an MCP server (planned). If that route fails,
# restore the skill from git history — it shipped at commit 36bc240.
echo "==> Skill: removed in favor of an MCP server (planned — see DECISIONS.md)"
echo "    fallback: preserved in git history at 36bc240"
echo "    (git show 36bc240:.agents/skills/delegate-openhands/SKILL.md)"

# ---- NIM connectivity ping --------------------------------------------------
echo "==> Pinging NIM with bare model ID '${DEFAULT_MODEL}'"
HTTP_CODE="$(curl -s -o /tmp/nim-ping.json -w '%{http_code}' \
  -X POST "${BASE_URL}/chat/completions" \
  -H "Authorization: Bearer ${NVIDIA_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"${DEFAULT_MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}],\"max_tokens\":8}")"
rm -f /tmp/nim-ping.json
if [[ "$HTTP_CODE" == "200" ]]; then
  echo "==> NIM ping OK (HTTP 200)"
else
  echo "==> NIM ping returned HTTP ${HTTP_CODE} — check the key, model ID, and rate limits"
  echo "    (rate limit: ~40 RPM free baseline; see docs/WHY.md)"
  exit 1
fi

cat <<'NEXT'

Setup complete. Next:
  1. Smoke test:  ./bin/smoke-test.sh
  2. Delegate:    ./bin/delegate.sh -t "your task" [-m minimaxai/minimax-m3]
  3. From Freebuff: an MCP delegate tool is planned (see DECISIONS.md); until
     it ships, delegate from the terminal via ./bin/delegate.sh.
NEXT
