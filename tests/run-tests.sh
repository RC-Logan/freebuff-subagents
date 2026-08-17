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
# Tested on: macOS 27 only (bash 3.2, BSD coreutils). Platform coverage is
# macOS-only until this suite is run and passes on another platform.
#
# Usage: ./tests/run-tests.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOCKS="$ROOT/tests/mocks"
WORK="$(mktemp -d /tmp/oh-tests-XXXX)"
RESTORED=0
ENV_FILE="$ROOT/.env"
# Simulate a fresh clone: move any real .env aside so tests control all env vars
# (delegate.sh sources .env when present). Restored on exit.
if [[ -f "$ENV_FILE" ]]; then
  mv "$ENV_FILE" "$ENV_FILE.suite-backup"
  RESTORED=1
fi
trap 'rm -rf "$WORK"; if [[ "$RESTORED" == "1" ]]; then mv "$ENV_FILE.suite-backup" "$ENV_FILE"; fi' EXIT

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
containsF() { # containsF <desc> <file> <needle> — fixed string, no regex metachars
  if grep -Fq -- "$3" "$2"; then ok "$1"; else bad "$1 (missing '$3' in $2)"; fi
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
export SANDBOX_VOLUMES="$T/dir:/workspace:rw"

"$ROOT/bin/delegate.sh" -t "hello task" -d "$T/dir" -m minimaxai/minimax-m3 > "$T/out.log" 2>&1
check "delegation exit 0" "$?" "0"
contains "NVIDIA key reaches subprocess" "$ENV_DUMP" "NVIDIA_API_KEY=nvapi-test-789"
contains "RUNTIME=docker passed to subprocess" "$ENV_DUMP" "RUNTIME=docker"
contains "SANDBOX_VOLUMES passed to subprocess" "$ENV_DUMP" "SANDBOX_VOLUMES=$T/dir:/workspace:rw"
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

# ---- sandbox enforcement ----------------------------------------------------
unset RUNTIME ALLOW_PROCESS_SANDBOX
"$ROOT/bin/delegate.sh" -t "sandbox check" > /dev/null 2>&1
contains "RUNTIME=docker passed to subprocess" "$ENV_DUMP" "RUNTIME=docker"

export RUNTIME="process"
set +e
"$ROOT/bin/delegate.sh" -t "unsafe" > "$T/refuse.log" 2>&1
RC=$?
set -e
check "process sandbox refused without opt-in" "$RC" "3"
contains "refusal explains opt-in" "$T/refuse.log" "ALLOW_PROCESS_SANDBOX"

export ALLOW_PROCESS_SANDBOX="1"
"$ROOT/bin/delegate.sh" -t "process allowed" > /dev/null 2>&1
check "process sandbox allowed with opt-in" "$?" "0"
contains "RUNTIME=process passed through" "$ENV_DUMP" "RUNTIME=process"
unset RUNTIME ALLOW_PROCESS_SANDBOX

# ---- role resolution ----------------------------------------------------------
echo "== delegate.sh: role resolution"
"$ROOT/bin/delegate.sh" -t "build a button" -r browser-use -d "$T/dir" > /dev/null 2>&1
check "role browser-use exits 0" "$?" "0"
contains "role pins vision model" "$ENV_DUMP" "LLM_MODEL=openai/minimaxai/minimax-m3"
contains "role operating rules injected" "$HOME/.mock-task.dump" "Operating rules: browser-use"
contains "user task present after rules" "$HOME/.mock-task.dump" "build a button"

"$ROOT/bin/delegate.sh" -t "summarize" -r researcher > /dev/null 2>&1
contains "researcher role uses GLM" "$ENV_DUMP" "LLM_MODEL=openai/z-ai/glm-5.2"
contains "researcher rules injected" "$HOME/.mock-task.dump" "Operating rules: researcher"

"$ROOT/bin/delegate.sh" -t "review" -r code-reviewer -m minimaxai/minimax-m3 > /dev/null 2>&1
contains "explicit -m overrides role model" "$ENV_DUMP" "LLM_MODEL=openai/minimaxai/minimax-m3"

set +e
"$ROOT/bin/delegate.sh" -t "x" -r bogus-role > "$T/badrole.log" 2>&1
RC=$?
set -e
check "unknown role rejected" "$RC" "3"

# ---- pluggable providers -------------------------------------------------------
echo "== delegate.sh: pluggable providers"
unset TEXT_MODEL TEXT_API_KEY TEXT_BASE_URL VISION_MODEL VISION_API_KEY VISION_BASE_URL

export TEXT_MODEL="my-text-model"
export TEXT_API_KEY="text-key-123"
export TEXT_BASE_URL="https://text.example/v1"
"$ROOT/bin/delegate.sh" -t "edit" -r code-editor > /dev/null 2>&1
contains "text provider model used" "$ENV_DUMP" "LLM_MODEL=openai/my-text-model"
contains "text provider key used" "$ENV_DUMP" "LLM_API_KEY=text-key-123"
contains "text provider base used" "$ENV_DUMP" "LLM_BASE_URL=https://text.example/v1"

# vision falls back to the text provider when VISION_* is unset (single-model setup)
"$ROOT/bin/delegate.sh" -t "browse" -r browser-use > /dev/null 2>&1
contains "vision falls back to text model" "$ENV_DUMP" "LLM_MODEL=openai/my-text-model"
contains "vision falls back to text key" "$ENV_DUMP" "LLM_API_KEY=text-key-123"

# vision provider overrides text
unset VISION_MODEL VISION_API_KEY VISION_BASE_URL
export VISION_MODEL="my-vision-model"
export VISION_API_KEY="vision-key-456"
export VISION_BASE_URL="https://vision.example/v1"
"$ROOT/bin/delegate.sh" -t "browse" -r browser-use > /dev/null 2>&1
contains "vision provider model used" "$ENV_DUMP" "LLM_MODEL=openai/my-vision-model"
contains "vision provider key used" "$ENV_DUMP" "LLM_API_KEY=vision-key-456"
contains "vision provider base used" "$ENV_DUMP" "LLM_BASE_URL=https://vision.example/v1"

unset TEXT_MODEL TEXT_API_KEY TEXT_BASE_URL VISION_MODEL VISION_API_KEY VISION_BASE_URL

# no key anywhere fails fast
set +e
env -u NVIDIA_API_KEY -u TEXT_API_KEY -u VISION_API_KEY \
  "$ROOT/bin/delegate.sh" -t "nokey" > "$T/nokey.log" 2>&1
RC=$?
set -e
check "missing API key rejected" "$RC" "1"

# ---- env loader precedence -----------------------------------------------------
echo "== env loader: precedence"
LT="$WORK/lt"; mkdir -p "$LT"
printf 'PRE_TEST=file-value\nUNSET_TEST=file-only\nEXPAND_TEST=${HOME}/x\n' > "$LT/.env"
(
  cd "$LT"
  export PRE_TEST=env-value
  # shellcheck disable=SC1091
  source "$ROOT/lib/env.sh"
  load_env
  test "$PRE_TEST" = "env-value" \
    && test "${UNSET_TEST:-}" = "file-only" \
    && test "${EXPAND_TEST:-}" = "$HOME/x"
)
check 'env loader: env wins, file fills, ${HOME} expands' "$?" "0"

# ---- check-env.sh -------------------------------------------------------------
echo "== check-env.sh: dry-run resolution"
export TEXT_MODEL="my-text"
export TEXT_API_KEY="key1234567890"
export TEXT_BASE_URL="https://text.example/v1"
"$ROOT/bin/check-env.sh" > "$T/check.log" 2>&1
check "check-env exits 0 with key" "$?" "0"
contains "check-env shows text model" "$T/check.log" "my-text"
containsF "check-env masks key" "$T/check.log" "key1****7890"
set +e
env -u NVIDIA_API_KEY -u TEXT_API_KEY -u VISION_API_KEY \
  "$ROOT/bin/check-env.sh" > /dev/null 2>&1
RC=$?
set -e
check "check-env fails without key" "$RC" "1"
unset TEXT_MODEL TEXT_API_KEY TEXT_BASE_URL

export MOCK_DOCKER_STATUS="up"
"$ROOT/bin/check-env.sh" > "$T/check.log" 2>&1
containsF "check-env reports docker running" "$T/check.log" "running (daemon up)"
export MOCK_DOCKER_STATUS="down"
"$ROOT/bin/check-env.sh" > "$T/check.log" 2>&1
containsF "check-env reports daemon down" "$T/check.log" "daemon NOT running"
unset MOCK_DOCKER_STATUS

# ===========================================================================
echo "== install.sh: config generation (V1), NIM ping payload, skill removal note"
T2="$WORK/t2"; mkdir -p "$T2/home" "$T2/curlbody"
export HOME="$T2/home"
export NVIDIA_API_KEY="nvapi-install-test"
export DEFAULT_MODEL="z-ai/glm-5.2"
export MOCK_CURL_BODY="$T2/curlbody/body.txt"
unset OPENHANDS_VERSION
touch "$HOME/.mock-override"   # simulate V1 CLI
export MOCK_DOCKER_STATUS="down"

"$ROOT/bin/install.sh" > "$T2/install.log" 2>&1
check "install.sh exits 0 (V1 path)" "$?" "0"
contains "install.sh warns when Docker unavailable" "$T2/install.log" "Docker is not available"
unset MOCK_DOCKER_STATUS
test -f "$T2/home/.openhands/agent_settings.json"; RC=$?
check "V1 config file written" "$RC" "0"
contains "config model has openai/ prefix" "$T2/home/.openhands/agent_settings.json" 'openai/z-ai/glm-5.2'
contains "config base URL" "$T2/home/.openhands/agent_settings.json" 'https://integrate.api.nvidia.com/v1'
contains "config api key" "$T2/home/.openhands/agent_settings.json" 'nvapi-install-test'
contains "install.sh notes the skill removal" "$T2/install.log" "MCP server"
contains "install.sh names the fallback tag" "$T2/install.log" "skill-fallback"
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
echo "== install.sh: invalid RUNTIME rejected"
T4="$WORK/t4"; mkdir -p "$T4/home" "$T4/curlbody"
export HOME="$T4/home"
export MOCK_CURL_BODY="$T4/curlbody/body.txt"
export RUNTIME="bogus"
set +e
"$ROOT/bin/install.sh" > "$T4/install.log" 2>&1
RC=$?
set -e
check "invalid RUNTIME rejected by install.sh" "$RC" "1"
unset RUNTIME

# ===========================================================================
echo "== install.sh: skill removed (no skills-dir machinery, no copy)"
T5="$WORK/t5"; mkdir -p "$T5/home" "$T5/project" "$T5/curlbody"
export HOME="$T5/home"
export NVIDIA_API_KEY="nvapi-install-test"
export MOCK_CURL_BODY="$T5/curlbody/body.txt"
unset OPENHANDS_VERSION

( cd "$T5/project" && "$ROOT/bin/install.sh" > "$T5/install.log" 2>&1 )
RC=$?
check "install.sh exits 0 from project cwd" "$RC" "0"
test ! -e "$T5/project/.agents/skills"; RC=$?
check "no skills copy happens (feature removed)" "$RC" "0"
contains "install.sh still notes the fallback" "$T5/install.log" "git history"

# ===========================================================================
echo
echo "== results: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -gt 0 ]]; then
  echo "== test suite FAILED"
  exit 1
fi
echo "== test suite PASSED — safe to proceed to a real run"
