#!/bin/bash
# Tests for the snapshot path-form fix in _lib-protected-state.sh (local
# customisation, ticket #8). pt_init must compare the session pin and the
# snapshot ops_root in the same physical form, and store project_dir in
# physical form, so that Git Bash's D:/... vs /d/... (or any equivalent
# non-canonical path) does not block every governed Bash command.
set -u
HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0

mkdir -p "$TMP/ops/sub" "$TMP/proj/sub" "$TMP/other" "$TMP/pins"
OPS="$(cd "$TMP/ops" && pwd -P)"
PROJ="$(cd "$TMP/proj" && pwd -P)"
SID="pathform-test"
printf '%s\n' "$OPS" > "$TMP/pins/ops-root-$SID"
mkdir -p "$TMP/pins/gate-session-$SID"

snapshot() {
  jq -n --arg o "$1" --arg p "$2" '{ops_root:$o, project_dir:$p, settings:{}}' \
    > "$TMP/pins/gate-session-$SID/snapshot.json"
}

# Runs pt_init in a subshell; prints "<rc> <PT_PROJECT>".
init() {
  (
    export APEXYARD_OPS_PIN_DIR="$TMP/pins"
    # shellcheck source=/dev/null
    . "$HOOKS/_lib-protected-state.sh"
    pt_init "{\"session_id\":\"$SID\"}"
    rc=$?
    printf '%s %s\n' "$rc" "${PT_PROJECT:-}"
  )
}

expect() {
  local want="$1" label="$2" got="$3"
  if [ "$got" = "$want" ]; then echo "ok   $label"; else echo "FAIL $label: want '$want' got '$got'"; fail=1; fi
}

snapshot "$OPS" "$PROJ"
expect "0 $PROJ" "canonical snapshot paths" "$(init)"

snapshot "$OPS/sub/.." "$PROJ/sub/.."
expect "0 $PROJ" "equivalent non-canonical snapshot paths are accepted and normalised" "$(init)"

snapshot "$TMP/other" "$PROJ"
expect "2" "snapshot ops_root for a different directory is rejected" "$(init | cut -d' ' -f1)"

snapshot "$TMP/missing-dir" "$PROJ"
expect "2" "snapshot ops_root that does not resolve is rejected" "$(init | cut -d' ' -f1)"

if command -v cygpath >/dev/null 2>&1; then
  snapshot "$(cygpath -m "$OPS")" "$(cygpath -m "$PROJ")"
  expect "0 $PROJ" "Windows mixed form (D:/...) snapshot paths" "$(init)"
else
  echo "skip Windows mixed-form case (no cygpath)"
fi

if [ "$fail" -ne 0 ]; then echo FAIL; exit 1; fi
echo PASS
