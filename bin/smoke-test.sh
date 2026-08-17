#!/usr/bin/env bash
# End-to-end smoke test: one headless delegation against NVIDIA NIM.
# Usage: ./bin/smoke-test.sh [-m <nim-model-id>]   (default: DEFAULT_MODEL from .env)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

MODEL=""
while getopts "m:h" opt; do
  case "$opt" in
    m) MODEL="$OPTARG" ;;
    h) echo "usage: smoke-test.sh [-m model-id]"; exit 0 ;;
    *) echo "usage: smoke-test.sh [-m model-id]" >&2; exit 2 ;;
  esac
done

WORK_DIR="$(mktemp -d /tmp/oh-smoke-XXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT

ARGS=(-f tasks/smoke-task.md -d "$WORK_DIR")
if [[ -n "$MODEL" ]]; then ARGS+=(-m "$MODEL"); fi

set +e
./bin/delegate.sh "${ARGS[@]}"
STATUS=$?
set -e

if [[ "$STATUS" -ne 0 ]]; then
  echo "SMOKE TEST FAILED: openhands exited with ${STATUS}" >&2
  exit "$STATUS"
fi

if [[ ! -f "$WORK_DIR/test_nim.py" ]]; then
  echo "SMOKE TEST FAILED: test_nim.py was not created" >&2
  exit 1
fi

echo "SMOKE TEST PASSED"
