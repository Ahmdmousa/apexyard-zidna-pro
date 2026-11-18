#!/bin/bash
# Tests for the Windows path fixes in block-protected-target-writes.sh and
# _lib-protected-state.sh (local customisation, ticket #11).
# - Edit/Write targets in drive-letter form (D:\...\.claude\settings.json)
#   must be judged as absolute paths, not prefixed with the cwd.
# - Bash operands written with backslashes ('.claude\settings.json') must
#   match the protected tokens.
set -u
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/_test-session-isolation.sh"
HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

mkdir -p "$TMP/ops/.claude/hooks" "$TMP/ops/src" "$TMP/pins"
: > "$TMP/ops/.claude/settings.json"; : > "$TMP/ops/.claude/hooks/x.sh"; : > "$TMP/ops/src/app.ts"
OPS="$(cd "$TMP/ops" && pwd -P)"
SID="winpath-test"
printf '%s\n' "$OPS" > "$TMP/pins/ops-root-$SID"
mkdir -p "$TMP/pins/gate-session-$SID"
jq -n --arg o "$OPS" '{ops_root:$o, project_dir:$o, settings:{}}' > "$TMP/pins/gate-session-$SID/snapshot.json"

gate() {
  printf '%s' "$1" | APEXYARD_OPS_PIN_DIR="$TMP/pins" CLAUDE_CODE_SESSION_ID="$SID" CLAUDE_PROJECT_DIR="$OPS" \
    bash "$HOOKS/block-protected-target-writes.sh" >/dev/null 2>&1
  echo $?
}
edit() { jq -nc --arg s "$SID" --arg w "$OPS" --arg f "$1" '{session_id:$s,cwd:$w,tool_name:"Edit",tool_input:{file_path:$f,old_string:"a",new_string:"b"}}'; }
bashc() { jq -nc --arg s "$SID" --arg w "$OPS" --arg c "$1" '{session_id:$s,cwd:$w,tool_name:"Bash",tool_input:{command:$c}}'; }
expect() {
  local want="$1" label="$2" got="$3"
  if [ "$got" = "$want" ]; then echo "ok   rc=$got  $label"; else echo "FAIL want=$want got=$got  $label"; fail=1; fi
}

expect 2 "Edit settings.json (POSIX path)" "$(gate "$(edit "$OPS/.claude/settings.json")")"
expect 0 "Edit an ordinary file (POSIX path)" "$(gate "$(edit "$OPS/src/app.ts")")"
expect 2 "Bash cp to quoted backslash settings path" "$(gate "$(bashc "cp x '.claude\\settings.json'")")"
expect 2 "Bash redirect to quoted backslash hook path" "$(gate "$(bashc 'echo x > ".claude\\hooks\\x.sh"')")"
expect 0 "Bash git status" "$(gate "$(bashc 'git status')")"

if command -v cygpath >/dev/null 2>&1; then
  WIN_BS="$(cygpath -w "$OPS")"
  WIN_FS="$(cygpath -m "$OPS")"
  expect 2 "Edit settings.json (D:\\ form)" "$(gate "$(edit "$WIN_BS\\.claude\\settings.json")")"
  expect 2 "Edit a hook (D:/ form)" "$(gate "$(edit "$WIN_FS/.claude/hooks/x.sh")")"
  expect 0 "Edit an ordinary file (D:\\ form)" "$(gate "$(edit "$WIN_BS\\src\\app.ts")")"
  expect 2 "Bash cp to quoted D:\\ settings path" "$(gate "$(bashc "cp x '$WIN_BS\\.claude\\settings.json'")")"
else
  echo "skip drive-letter cases (no cygpath)"
fi

if [ "$fail" -ne 0 ]; then echo FAIL; exit 1; fi
echo PASS
