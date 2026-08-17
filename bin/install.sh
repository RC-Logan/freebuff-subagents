#!/usr/bin/env bash
# Bootstrap: install OpenHands, wire NVIDIA NIM, install the Freebuff skill.
# Idempotent — safe to re-run.
#
# Usage: ./bin/install.sh
# Reads: .env (copy from .env.example) or the current environment.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

# ---- load .env if present -------------------------------------------------
if [[ -f .env ]]; then
  echo "==> Loading .env"
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

# ---- preconditions ---------------------------------------------------------
: "${NVIDIA_API_KEY:?NVIDIA_API_KEY is required (set it in .env)}"
DEFAULT_MODEL="${DEFAULT_MODEL:-z-ai/glm-5.2}"
BASE_URL="https://integrate.api.nvidia.com/v1"
RUNTIME="${RUNTIME:-docker}"
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

# ---- install the Freebuff skill -------------------------------------------
if [[ -n "${FREE_BUFF_SKILLS_DIR:-}" ]]; then
  echo "==> Installing skill into ${FREE_BUFF_SKILLS_DIR}"
  mkdir -p "$FREE_BUFF_SKILLS_DIR"
  cp -R skills/delegate_to_openhands "$FREE_BUFF_SKILLS_DIR/"
  echo "    NOTE: verify this is the real skills dir for your Freebuff install"
  echo "    (see docs/WHY.md §1c audit item #4)"
else
  echo "==> FREE_BUFF_SKILLS_DIR not set — skipping skill install"
fi

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
  3. From Freebuff: invoke the delegate_to_openhands skill (verify the skills path above).
NEXT
