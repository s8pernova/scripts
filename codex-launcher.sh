#!/usr/bin/env bash
set -u

NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/codex-launcher"

LOCK_TIMEOUT=5
UPDATE_TIMEOUT=20
INSTALL_TIMEOUT=180

# Load the user's NVM-managed Node installation.
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    # shellcheck source=/dev/null
    source "$NVM_DIR/nvm.sh"

    nvm use --silent default >/dev/null 2>&1 ||
        nvm use --silent node >/dev/null 2>&1 ||
        true
fi

npm_bin="$(command -v npm || true)"

if [[ -z "$npm_bin" ]]; then
    echo "codex-launcher: npm was not found" >&2
    exit 127
fi

npm_prefix="$("$npm_bin" prefix -g)"
real_codex="$npm_prefix/bin/codex"

log_file="$CACHE_DIR/update.log"
lock_file="$CACHE_DIR/update.lock"

mkdir -p "$CACHE_DIR"

update_codex() {
    local installed_version=""
    local latest_version=""

    if [[ -x "$real_codex" ]]; then
        installed_version="$(
            "$real_codex" --version 2>/dev/null |
                awk '{print $NF}'
        )"
    fi

    latest_version="$(
        timeout "${UPDATE_TIMEOUT}s" \
            "$npm_bin" view @openai/codex@latest version --silent
    )" || return 0

    [[ -n "$latest_version" ]] || return 0
    [[ "$installed_version" != "$latest_version" ]] || return 0

    printf '%s Updating Codex: %s -> %s\n' \
        "$(date -Iseconds)" \
        "${installed_version:-missing}" \
        "$latest_version"

    timeout "${INSTALL_TIMEOUT}s" \
        "$npm_bin" install -g @openai/codex@latest \
        --no-audit \
        --no-fund
}

# Run the update before starting Codex.
# Failures are logged, then the currently installed version is started.
(
    flock -w "$LOCK_TIMEOUT" 9 || exit 0
    update_codex
) 9>"$lock_file" >>"$log_file" 2>&1 || true

if [[ ! -x "$real_codex" ]]; then
    echo "codex-launcher: Codex is unavailable at $real_codex" >&2
    exit 127
fi

exec "$real_codex" "$@"