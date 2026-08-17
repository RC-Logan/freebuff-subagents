#!/usr/bin/env bash
# Dry-run: print the resolved configuration from .env / environment.
# Nothing is installed and no API is called. Fails (exit 1) if no key is set.
#
# Usage: ./bin/check-env.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/env.sh"
load_env

BASE_URL="${BASE_URL:-https://integrate.api.nvidia.com/v1}"
DEFAULT_MODEL="${DEFAULT_MODEL:-z-ai/glm-5.2}"
RUNTIME="${RUNTIME:-docker}"
TEXT_KEY="${TEXT_API_KEY:-${NVIDIA_API_KEY:-}}"
VISION_KEY="${VISION_API_KEY:-${TEXT_API_KEY:-${NVIDIA_API_KEY:-}}}"
OH="$(command -v openhands 2>/dev/null || true)"

mask() {
  local v="$1"
  if [[ -z "$v" ]]; then echo "(not set)"; else echo "${v:0:4}****${v: -4}"; fi
}

echo "Resolved configuration:"
echo "  text model:   ${TEXT_MODEL:-$DEFAULT_MODEL}"
echo "  text base:    ${TEXT_BASE_URL:-$BASE_URL}"
echo "  text key:     $(mask "$TEXT_KEY")"
echo "  vision model: ${VISION_MODEL:-${TEXT_MODEL:-$DEFAULT_MODEL}}"
echo "  vision base:  ${VISION_BASE_URL:-${TEXT_BASE_URL:-$BASE_URL}}"
echo "  vision key:   $(mask "$VISION_KEY")"
echo "  sandbox:      ${RUNTIME}"
echo "  skills dir:   ${FREE_BUFF_SKILLS_DIR:-(not set)}"
echo "  openhands:    ${OH:-not installed (run ./bin/install.sh)}"

if [[ -z "$TEXT_KEY" ]]; then
  echo
  echo "ERROR: no API key found. Set NVIDIA_API_KEY (or TEXT_API_KEY) in .env." >&2
  exit 1
fi

echo
echo "OK: key present — ready for ./bin/install.sh"
