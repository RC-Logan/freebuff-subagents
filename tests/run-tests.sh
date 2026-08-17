#!/usr/bin/env bash
# Pre-run test suite for bin/install.sh and bin/delegate.sh.
#
# Runs everything against mock binaries (tests/mocks) in a sandboxed HOME —
# nothing is installed, no real network calls, no NIM API spend, no changes to
# the real ~/.openhands or Freebuff. Use this before the first real run.
#
# The mock openhands channels its config through HOME (see tests/mocks/openhands),
# because delegate.sh runs the real binary under `env -i`.
#
# Usage: ./tests/run-tests.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOCKS="$ROOT/tests/mocks"
WORK="$(mktemp -d /tmp/oh-tests-XXXX)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; }
check() { # check <desc> <actual> <expected>
  if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (got '$2', want '$3')"; fi
}
contains() { # contains <desc> <file> <needle>
  if grep -q -- "$3" "$2"; then ok "$1"; else bad "$1 (missing '$3' in $2)"; fi
}
not_contains() { # not_contains <desc> <file> <forbidden>
  if grep -q -- "$3" "$2"; then bad "$1 (found forbidden '$3' in $2)"; else ok "$1"; fi
}

export PATH="$MOCKS:$PATH"

# ===========================================================================
echo "== delegate.sh: env sanitization, model routing, flags, exit codes"
T="$WORK/t1"; mkdir -p "$T/home" "$T/dir"
export HOME="$T/home"
ENV_DUMP="$HOME/.mock-env.dump"
ARGS_DUMP="$HOME/.mock-args.dump"
# Simulated secrets that must NEVER reach the subprocess:
export FREE_BUFF_SESSION_TOKEN="secret-session-123"
export FREEBUFF_API_KEY="sk-freebuff-456"
export NVIDIA_API_KEY="nvapi-test-789"

"$ROOT/bin/delegate.sh" -t "hello task" -d "$T/dir" -m minimaxai/minimax-m3 > "$T/out.log" 2>&1
check "delegation exit 0" "$?" "0"
contains "NVIDIA key reaches subprocess" "$ENV_DUMP" "NVIDIA_API_KEY=nvapi-test-789"
contains "model routed with openai/ prefix" "$ENV_DUMP" "LLM_MODEL=openai/minimaxai/minimax-m3"
contains "base URL set" "$ENV_DUMP" "LLM_BASE_URL=https://integrate.api.nvidia.com/v1"
not_contains "Freebuff session token does NOT leak" "$ENV_DUMP" "FREE_BUFF_SESSION_TOKEN"
not_contains "Freebuff API key does NOT leak" "$ENV_DUMP" "FREEBUFF_API_KEY"
contains "invoked headless" "$ARGS_DUMP" "--headless"
contains "task passed via -f file" "$ARGS_DUMP" "-f"

printf '1' > "$HOME/.mock-exit"
set +e
"$ROOT/bin/delegate.sh" -t "failing task" > /dev/null 2>&1
RC=$?
set -e
check "exit code 1 propagates" "$RC" "1"
rm -f "$HOME/.mock-exit"

"$ROOT/bin/delegate.sh" -t "default model" > /dev/null 2>&1
contains "default model is GLM-5.2" "$ENV_DUMP" "LLM_MODEL=openai/z-ai/glm-5.2"

touch "$HOME/.mock-override"
"$ROOT/bin/delegate.sh" -t "v1 flags" > /dev/null 2>&1
contains "V1: --override-with-envs flag" "$ARGS_DUMP" "--override-with-envs"
contains "V1: --json flag" "$ARGS_DUMP" "--json"
rm -f "$HOME/.mock-override"

# ===========================================================================
echo "== install.sh: config generation (V1), skill install, NIM ping payload"
T2="$WORK/t2"; mkdir -p "$T2/home" "$T2/skills" "$T2/curlbody"
export HOME="$T2/home"
export NVIDIA_API_KEY="nvapi-install-test"
export DEFAULT_MODEL="z-ai/glm-5.2"
export FREE_BUFF_SKILLS_DIR="$T2/skills"
export MOCK_CURL_BODY="$T2/curlbody/body.txt"
unset OPENHANDS_VERSION
touch "$HOME/.mock-override"   # simulate V1 CLI

"$ROOT/bin/install.sh" > "$T2/install.log" 2>&1
check "install.sh exits 0 (V1 path)" "$?" "0"
test -f "$T2/home/.openhands/agent_settings.json"; RC=$?
check "V1 config file written" "$RC" "0"
contains "config model has openai/ prefix" "$T2/home/.openhands/agent_settings.json" 'openai/z-ai/glm-5.2'
contains "config base URL" "$T2/home/.openhands/agent_settings.json" 'https://integrate.api.nvidia.com/v1'
contains "config api key" "$T2/home/.openhands/agent_settings.json" 'nvapi-install-test'
test -f "$T2/skills/delegate_to_openhands/SKILL.md"; RC=$?
check "skill copied to skills dir" "$RC" "0"
contains "NIM ping uses BARE model id" "$T2/curlbody/body.txt" '"model":"z-ai/glm-5.2"'
not_contains "NIM ping body has no openai/ prefix" "$T2/curlbody/body.txt" 'openai/'

# ===========================================================================
echo "== install.sh: legacy V0 config.toml fallback"
T3="$WORK/t3"; mkdir -p "$T3/home" "$T3/curlbody"
export HOME="$T3/home"
export MOCK_CURL_BODY="$T3/curlbody/body.txt"
rm -f "$T2/home/.mock-override"   # keep V1 HOME clean; V0 HOME has none by default

"$ROOT/bin/install.sh" > "$T3/install.log" 2>&1
check "install.sh exits 0 (V0 path)" "$?" "0"
test -f "$T3/home/.openhands/config.toml"; RC=$?
check "V0 config.toml written" "$RC" "0"
contains "V0 model has openai/ prefix" "$T3/home/.openhands/config.toml" 'openai/z-ai/glm-5.2'
contains "V0 max_iterations" "$T3/home/.openhands/config.toml" 'max_iterations = 25'

# ===========================================================================
echo
echo "== results: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -gt 0 ]]; then
  echo "== test suite FAILED"
  exit 1
fi
echo "== test suite PASSED — safe to proceed to a real run"
