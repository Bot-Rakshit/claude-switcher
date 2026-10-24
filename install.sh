#!/bin/bash
# Installs (or updates) claude-sync:
#   curl -fsSL https://raw.githubusercontent.com/Bot-Rakshit/claude-switcher/main/install.sh | bash
set -euo pipefail

RAW="https://raw.githubusercontent.com/Bot-Rakshit/claude-switcher/main"
BIN_DIR="${CLAUDE_SYNC_BIN_DIR:-$HOME/.local/bin}"
DEST="$BIN_DIR/claude-sync"

say()  { printf '%s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "claude-sync is for the Claude desktop app on macOS."

# A python3 that runs without prompting. On Macs without the developer tools,
# /usr/bin/python3 is a stub that pops up an installer, so only use it when they're there.
has_clt() { xcode-select -p >/dev/null 2>&1; }
ok_python() {
  [ -x "$1" ] || return 1
  if [ "$1" = "/usr/bin/python3" ] && ! has_clt; then return 1; fi
  "$1" -c 'import sys; sys.exit(sys.version_info < (3, 8))' >/dev/null 2>&1
}
PY=""
for c in /usr/bin/python3 "$(command -v python3 || true)" /opt/homebrew/bin/python3 /usr/local/bin/python3; do
  if [ -n "$c" ] && ok_python "$c"; then PY="$c"; break; fi
done
[ -n "$PY" ] || fail "needs Python 3.8+. Run \`xcode-select --install\` (or \`brew install python\`), then re-run this."

# From a clone, install the local copy; when piped from curl, download it.
TMP="$(mktemp -t claude-sync.XXXXXX)"
trap 'rm -f "$TMP"' EXIT
SRC="${BASH_SOURCE[0]:-}"
if [ -n "$SRC" ] && [ -f "$SRC" ] && [ -f "$(dirname "$SRC")/claude-sync" ]; then
  cp "$(dirname "$SRC")/claude-sync" "$TMP"
else
  curl -fsSL --retry 3 --connect-timeout 15 --max-time 120 "$RAW/claude-sync" -o "$TMP" \
    || fail "download failed (network?). Try again in a moment."
fi

# Pin the shebang to the python we checked, so it never hits the stub.
{ printf '#!%s\n' "$PY"; tail -n +2 "$TMP"; } > "$TMP.new" && mv "$TMP.new" "$TMP"
"$PY" "$TMP" --version >/dev/null 2>&1 || fail "the downloaded script doesn't run with $PY"

mkdir -p "$BIN_DIR"
install -m 755 "$TMP" "$DEST"
say "Installed $("$DEST" --version) to $DEST (python: $PY)"

# Refresh the background agent if it was on (paths may have changed).
if [ -f "$HOME/Library/LaunchAgents/com.user.claude-sync.plist" ]; then
  "$DEST" install >/dev/null && say "Auto-sync agent refreshed."
fi

if [ ! -d "$HOME/Library/Application Support/Claude" ]; then
  say ""
  say "Note: Claude desktop isn't set up on this Mac yet. Get it from https://claude.ai/download"
fi

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    say ""
    SHOWN="${BIN_DIR/#$HOME/\$HOME}"
    say "$SHOWN isn't on your PATH. Add it with:"
    say "  echo 'export PATH=\"$SHOWN:\$PATH\"' >> ~/.zshrc && source ~/.zshrc"
    ;;
esac

cat <<'EOF'

Next:
  claude-sync              see what's shared and what would change
  claude-sync add          restart Claude at sign-in to add another account
  claude-sync accounts     list accounts;  claude-sync use 2  to switch
  claude-sync install      keep sessions synced in the background
EOF
