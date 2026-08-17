#!/usr/bin/env bash
# Run one OpenHands headless delegation against NVIDIA NIM.
#
# SECURITY: the subprocess gets a sanitized environment (env -i) containing
# ONLY the NVIDIA key and LLM routing vars — never Freebuff session tokens or
# other inherited secrets. The wrapper never echoes the API key.
#
# Usage:
#   ./bin/delegate.sh -t "task text" [-d working_dir] [-m <nim-model-id>]
#   ./bin/delegate.sh -f task.md      [-d working_dir] [-m <nim-model-id>]
#   ./bin/delegate.sh -t "task" -r <role>   (role from roles/<role>/, see ROLES.md)
#
# Exit codes: 0 = success, 1 = task failed, 2 = invalid args, 3 = unsafe config.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

TASK_TEXT=""
TASK_FILE=""
WORK_DIR=""
MODEL=""
ROLE=""

while getopts "t:f:d:m:r:h" opt; do
  case "$opt" in
    t) TASK_TEXT="$OPTARG" ;;
    f) TASK_FILE="$OPTARG" ;;
    d) WORK_DIR="$OPTARG" ;;
    m) MODEL="$OPTARG" ;;
    r) ROLE="$OPTARG" ;;
    h) sed -n '2,14p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "usage: delegate.sh -t text | -f file [-d dir] [-m model] [-r role]" >&2; exit 2 ;;
  esac
done

# ---- load .env --------------------------------------------------------------
if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

: "${NVIDIA_API_KEY:?NVIDIA_API_KEY is required (set it in .env)}"
MODEL="${MODEL:-${DEFAULT_MODEL:-}}"
BASE_URL="https://integrate.api.nvidia.com/v1"

# ---- role resolution ----------------------------------------------------------
# A role (roles/<name>/role.conf + prompt.md) pins the model and injects the
# role's operating rules into the task — deterministic capability behavior.
ROLE_PROMPT=""
if [[ -n "$ROLE" ]]; then
  ROLE_CONF="$SCRIPT_DIR/roles/$ROLE/role.conf"
  if [[ ! -f "$ROLE_CONF" ]]; then
    echo "ERROR: unknown role '$ROLE' (see roles/ and ROLES.md)" >&2
    exit 3
  fi
  ROLE_MODEL="$(grep -E '^model=' "$ROLE_CONF" | head -1 | cut -d= -f2- | tr -d ' "')"
  MODEL="${MODEL:-$ROLE_MODEL}"
  ROLE_PROMPT="$SCRIPT_DIR/roles/$ROLE/prompt.md"
fi
MODEL="${MODEL:-z-ai/glm-5.2}"

# ---- sandbox safety ----------------------------------------------------------
# Docker is the enforced default: agent commands run inside a container, and only
# the delegated working dir (+ SANDBOX_VOLUMES) is shared with the host.
# RUNTIME=process runs commands directly on this machine — refused unless the
# user explicitly opts in. RUNTIME is passed through env -i so the choice holds.
RUNTIME="${RUNTIME:-docker}"
SANDBOX_VOLUMES="${SANDBOX_VOLUMES:-}"
case "$RUNTIME" in
  docker|remote) ;;
  process)
    echo "WARNING: RUNTIME=process runs agent commands directly on your machine" >&2
    echo "         with your user permissions — no container isolation." >&2
    if [[ "${ALLOW_PROCESS_SANDBOX:-}" != "1" ]]; then
      echo "REFUSING to run. Set ALLOW_PROCESS_SANDBOX=1 to accept this explicitly." >&2
      exit 3
    fi
    ;;
  *)
    echo "ERROR: unknown RUNTIME '$RUNTIME' (expected docker | process | remote)" >&2
    exit 3
    ;;
esac

if [[ -z "$TASK_TEXT" && -z "$TASK_FILE" ]]; then
  echo "ERROR: provide a task with -t or -f" >&2
  exit 2
fi

export PATH="$HOME/.local/bin:$PATH"
command -v openhands >/dev/null 2>&1 || { echo "ERROR: openhands not found (run ./bin/install.sh)" >&2; exit 1; }

# ---- task file ---------------------------------------------------------------
TMP_TASK=""
if [[ -n "$TASK_TEXT" ]]; then
  TMP_TASK="$(mktemp /tmp/oh-task.XXXXXX)"
  printf '%s\n' "$TASK_TEXT" > "$TMP_TASK"
  TASK_FILE="$TMP_TASK"
fi
# Compose the final task: role operating rules (if any) + user task.
if [[ -n "$ROLE" && -f "$ROLE_PROMPT" ]]; then
  COMPOSED="$(mktemp /tmp/oh-task.XXXXXX)"
  cat "$ROLE_PROMPT" > "$COMPOSED"
  printf '\n\n# Task\n\n' >> "$COMPOSED"
  cat "$TASK_FILE" >> "$COMPOSED"
  rm -f "$TMP_TASK"
  TASK_FILE="$COMPOSED"
  TMP_TASK="$COMPOSED"
fi
# Make the task path absolute before any cd
TASK_FILE="$(cd "$(dirname "$TASK_FILE")" && pwd)/$(basename "$TASK_FILE")"

OUT_FILE="$(mktemp /tmp/oh-out.XXXXXX)"
MARKER=""
cleanup() { rm -f "$TMP_TASK" "$OUT_FILE" "$MARKER"; }
trap cleanup EXIT

if [[ -n "$WORK_DIR" ]]; then
  mkdir -p "$WORK_DIR"
  cd "$WORK_DIR"
  # Marker so we can list what the agent created/changed afterwards.
  MARKER="$WORK_DIR/.oh-marker"
  touch "$MARKER" 2>/dev/null || MARKER=""
fi

# ---- version-specific flags (string, not array: macOS bash 3.2 compat) ---------
EXTRA=""
if openhands --help 2>&1 | grep -q -- '--override-with-envs'; then
  EXTRA="$EXTRA --override-with-envs"
fi
if openhands --help 2>&1 | grep -q -- '--json'; then
  EXTRA="$EXTRA --json"
fi

echo "==> Delegating to openhands (model: ${MODEL})"
echo "    task: ${TASK_FILE##*/} | dir: ${PWD}"
echo "    sandbox: ${RUNTIME}${SANDBOX_VOLUMES:+ | volumes: ${SANDBOX_VOLUMES}}"

# Sanitized environment: only what OpenHands needs. No inherited secrets.
# shellcheck disable=SC2086
env -i \
  PATH="$PATH" \
  HOME="$HOME" \
  LANG="${LANG:-C.UTF-8}" \
  NVIDIA_API_KEY="$NVIDIA_API_KEY" \
  LLM_API_KEY="$NVIDIA_API_KEY" \
  LLM_MODEL="openai/${MODEL}" \
  LLM_BASE_URL="$BASE_URL" \
  RUNTIME="$RUNTIME" \
  SANDBOX_VOLUMES="$SANDBOX_VOLUMES" \
  openhands --headless $EXTRA -f "$TASK_FILE" > "$OUT_FILE" 2>&1
STATUS=$?

echo "==> exit code: ${STATUS} (0=success, 1=task failed, 2=invalid args, 3=unsafe config)"
if [[ -n "$MARKER" && -f "$MARKER" ]]; then
  echo "==> files changed/created by the agent:"
  find "$WORK_DIR" -type f ! -name '.oh-marker' -newer "$MARKER" 2>/dev/null \
    | sed "s|^$WORK_DIR/||" | head -20 || true
fi
if [[ -s "$OUT_FILE" ]]; then
  echo "==> last observations:"
  grep -a '"type": "observation"' "$OUT_FILE" | tail -5 \
    || tail -20 "$OUT_FILE" || true
fi

exit "$STATUS"
