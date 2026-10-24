#!/bin/bash
# End-to-end tests against a fake Claude data folder. Never touches the real app.
#   tests/run.sh [python]      (default: python3)
set -euo pipefail

PY="${1:-python3}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CS="$ROOT/claude-sync"
W="$(mktemp -d -t claude-sync-test.XXXXXX)"
trap 'rm -rf "$W"' EXIT

export CLAUDE_SYNC_APP_DIR="$W/app" CLAUDE_SYNC_PROJECTS="$W/projects"
export CLAUDE_SYNC_BACKUPS="$W/backups" CLAUDE_SYNC_PROFILES="$W/profiles"
export CLAUDE_SYNC_NO_APP=1

A1=aaaaaaaa-1111-4111-8111-111111111111; O1=11111111-aaaa-4aaa-8aaa-aaaaaaaaaaaa
A2=bbbbbbbb-2222-4222-8222-222222222222; O2=22222222-bbbb-4bbb-8bbb-bbbbbbbbbbbb
C1="$W/app/claude-code-sessions/$A1/$O1"; C2="$W/app/claude-code-sessions/$A2/$O2"
K1="$W/app/local-agent-mode-sessions/$A1/$O1"; K2="$W/app/local-agent-mode-sessions/$A2/$O2"

pass=0
ok()   { pass=$((pass + 1)); printf '  ok  %s\n' "$1"; }
die()  { printf 'FAIL  %s\n' "$1" >&2; exit 1; }
cs()   { "$PY" "$CS" "$@"; }
check() { if eval "$2"; then ok "$1"; else die "$1"; fi; }

session() {  # dir name transcript-id activity-ms
  mkdir -p "$1" "$W/projects/-proj"
  printf '{"sessionId":"%s","cliSessionId":"%s","lastActivityAt":%s,"title":"t"}' \
    "${2%.json}" "$3" "$4" > "$1/$2"
  touch "$W/projects/-proj/$3.jsonl"
}
config() {  # account token
  printf '{"userThemeMode":"dark","oauth:tokenCacheV2":"%s","lastKnownAccountUuid":"%s"}' "$2" "$1" \
    > "$W/app/config.json"
}

echo "python: $("$PY" --version 2>&1)"
check "--version" '[[ "$(cs --version)" == claude-sync* ]]'
check "missing app folder gives a clear error" \
  '! out=$(cs 2>&1) && [[ "$out" == *"not found"* ]]'

mkdir -p "$W/app"
config "$A1" token-a
session "$C1" local_s1.json t1 1000
session "$C2" local_s2.json t2 2000
mkdir -p "$K1/local_c1" "$K2"; echo data > "$K1/local_c1/audit.jsonl"
printf '{"cliSessionId":"c1","lastActivityAt":5,"emailAddress":"a@example.com"}' > "$K1/local_c1.json"

out=$(cs)
check "dry run reports changes" '[[ "$out" == *"+1 new"* ]]'
check "dry run writes nothing" '[ ! -e "$C2/local_s1.json" ]'

CLAUDE_SYNC_NO_APP=running cs --live --quiet
check "live: shares into the signed-out account" '[ -e "$C2/local_s1.json" ]'
check "live: leaves the signed-in account alone" '[ ! -e "$C1/local_s2.json" ]'

cs --live --quiet
check "app closed: full sync" '[ -e "$C1/local_s2.json" ]'
check "cowork: data folder linked, not copied" \
  '[ -L "$K2/local_c1" ] && [ "$(cat "$K2/local_c1/audit.jsonl")" = data ]'
check "second run is a no-op" '[[ "$(cs)" == *"Everything is in sync"* ]]'

session "$C2" local_s2.json t2 9000   # edited in account 2
cs --live --quiet
check "newest copy wins" 'grep -q 9000 "$C1/local_s2.json"'

rm "$C1/local_s1.json"                # deleted in account 1
cs --live --quiet
check "deletion spreads to other accounts" '[ ! -e "$C2/local_s1.json" ]'
check "deleted copy kept in backups" '[ -n "$(find "$W/backups" -name local_s1.json)" ]'
cs --live --quiet
check "deleted session doesn't come back" '[ ! -e "$C1/local_s1.json" ] && [ ! -e "$C2/local_s1.json" ]'

for i in 1 2 3 4 5 6 7 8; do session "$C1" "local_m$i.json" "m$i" 3000; done
cs --live --quiet
rm "$C2"/local_m*.json                # whole folder wiped (e.g. sign-out)
out=$(cs --live 2>&1)
check "wiped folder is refilled, not mass-deleted" \
  '[ -e "$C1/local_m1.json" ] && [ -e "$C2/local_m1.json" ]'

# Accounts: sign in once, switch without signing in again.
echo cookie-a > "$W/app/Cookies"; mkdir -p "$W/app/Local Storage"; echo ls-a > "$W/app/Local Storage/x"
check "current account listed before first save" '[[ "$(cs accounts)" == *"saved on first switch"* ]]'
cs rename aaaa Work
cs add >/dev/null
check "add: saves current sign-in" '[ -f "$W/profiles/$A1/auth.json" ]'
check "add: app starts signed out" '! grep -q oauth "$W/app/config.json" && [ ! -e "$W/app/Cookies" ]'
check "add: other settings kept" 'grep -q userThemeMode "$W/app/config.json"'
check "saved sign-in is private" '[ "$(stat -f %Lp "$W/profiles/$A1/auth.json")" = 600 ]'

config "$A2" token-b; echo cookie-b > "$W/app/Cookies"   # user signs in as account 2
cs use Work >/dev/null
check "use: restores account 1" 'grep -q token-a "$W/app/config.json" && [ "$(cat "$W/app/Cookies")" = cookie-a ]'
check "use: restores web storage" '[ "$(cat "$W/app/Local Storage/x")" = ls-a ]'
check "use: account 2 saved on the way out" 'grep -q token-b "$W/profiles/$A2/auth.json"'
cs use 2 >/dev/null
check "use by number switches back" 'grep -q token-b "$W/app/config.json"'
check "use: switching to the current account is a no-op" '[[ "$(cs use 2)" == *"Already signed in"* ]]'
check "accounts --json" \
  '"$PY" -c "import json,sys; d=json.load(sys.stdin); assert len(d)==2 and sum(a[\"active\"] for a in d)==1" <<< "$(cs accounts --json)"'
cs forget Work >/dev/null
check "forget removes a saved sign-in" '[ ! -e "$W/profiles/$A1" ]'

echo "all $pass tests passed"
