# Shared .env loader for bin/ scripts.
#
# Precedence: explicitly-set environment variables WIN over .env. Variables not
# already set in the environment are exported from .env (if present), with
# ${VAR} references expanded against the current environment.
#
# Usage:
#   source "$SCRIPT_DIR/lib/env.sh"
#   load_env [path-to-.env]

load_env() {
  local env_file="${1:-.env}"
  [[ -f "$env_file" ]] || return 0
  local line key val ref
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || continue
    key="${line%%=*}"
    # env vars win: skip keys already set (non-empty) in the environment
    [[ -n "${!key:-}" ]] && continue
    val="${line#*=}"
    # expand ${VAR} references against the current environment
    while [[ "$val" =~ \$\{([A-Za-z_][A-Za-z0-9_]*)\} ]]; do
      ref="${BASH_REMATCH[1]}"
      val="${val//\$\{$ref\}/${!ref:-}}"
    done
    export "$key=$val"
  done < "$env_file"
}
