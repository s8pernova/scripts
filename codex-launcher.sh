#!/bin/sh
set -eu

NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
NPM_PREFIX=""
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/codex-launcher"
LOCK_TIMEOUT=180
UPDATE_TIMEOUT=20
INSTALL_TIMEOUT=180

usage() {
  echo "Usage:"
  echo "  ./codex-launcher.sh [-d NVM_DIR] [-c CACHE_DIR] [-h]"
  echo
  echo "Defaults:"
  echo "  NVM_DIR=$NVM_DIR"
  echo "  CACHE_DIR=$CACHE_DIR"
  echo
  echo "Examples:"
  echo "  ./codex-launcher.sh"
  echo "  ./codex-launcher.sh -d /opt/nvm"
  echo "  ./codex-launcher.sh -c /tmp/codex-cache"
  exit 1
}

while getopts "d:c:h" opt; do
  case "$opt" in
    d) NVM_DIR="$OPTARG" ;;
    c) CACHE_DIR="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done

# Bootstrap nvm + node

if [ -s "$NVM_DIR/nvm.sh" ]; then
  # nvm must be sourced in a bash-compatible shell; re-exec under bash if
  # the current shell is not bash.
  if [ -z "${BASH_VERSION:-}" ]; then
    exec bash "$0" "$@"
  fi

  # shellcheck source=/dev/null
  . "$NVM_DIR/nvm.sh"

  nvm use --silent default >/dev/null 2>&1 ||
    nvm use --silent node >/dev/null 2>&1 ||
    true
fi

npm_bin="$(command -v npm || true)"

[ -n "$npm_bin" ] || { echo "ERROR: npm was not found"; exit 127; }

NPM_PREFIX="$("$npm_bin" prefix -g)"
real_codex="$NPM_PREFIX/bin/codex"

log_file="$CACHE_DIR/update.log"
lock_file="$CACHE_DIR/update.lock"

mkdir -p "$CACHE_DIR"

echo "NVM_DIR:    $NVM_DIR"
echo "NPM_PREFIX: $NPM_PREFIX"
echo "CACHE_DIR:  $CACHE_DIR"
echo "Codex:      $real_codex"
echo

# Background update

update_codex() {
  installed_version=""
  latest_version=""

  if [ -x "$real_codex" ]; then
    installed_version="$(
      "$real_codex" --version 2>/dev/null |
        awk '{print $NF}'
    )"
  fi

  latest_version="$(
    timeout "${UPDATE_TIMEOUT}s" "$npm_bin" view \
      @openai/codex@latest version \
      --silent
  )" || return 0

  [ -n "$latest_version" ] || return 0

  if [ "$installed_version" = "$latest_version" ]; then
    return 0
  fi

  printf '%s Updating Codex: %s -> %s\n' \
    "$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')" \
    "${installed_version:-missing}" \
    "$latest_version"

  timeout "${INSTALL_TIMEOUT}s" "$npm_bin" install -g \
    @openai/codex@latest \
    --no-audit \
    --no-fund
}

# Keep updater output away from Codex's stdout because the app may parse it.
(
  flock -w "$LOCK_TIMEOUT" 9 || exit 0
  update_codex
) 9>"$lock_file" >>"$log_file" 2>&1 || true

[ -x "$real_codex" ] || { echo "ERROR: Codex is unavailable at $real_codex"; exit 127; }

exec "$real_codex" "$@"