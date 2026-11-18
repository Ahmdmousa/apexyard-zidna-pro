#!/bin/bash
# Tests for block-protected-ref-api.sh (local customisation, ADR-0054, #4).
set -u
HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

run() {
  local cmd="$1"
  jq -nc --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}' \
    | bash "$HOOKS/block-protected-ref-api.sh" >/dev/null 2>&1
  echo $?
}

expect() {
  local want="$1" cmd="$2" got
  got=$(run "$cmd")
  if [ "$got" = "$want" ]; then
    echo "ok   rc=$got  $cmd"
  else
    echo "FAIL want=$want got=$got  $cmd"
    fail=1
  fi
}

# Blocked: ref moves, merges, commits via API, protection changes.
expect 2 'gh api -X PATCH repos/o/r/git/refs/heads/main -f sha=abc'
expect 2 'gh api --method POST repos/o/r/git/refs -f ref=refs/heads/main -f sha=abc'
expect 2 'gh api -X DELETE repos/o/r/git/refs/heads/main'
expect 2 'gh api repos/o/r/git/commits -f message=x -f tree=abc'
expect 2 'gh api -X PUT repos/o/r/pulls/7/merge'
expect 2 'gh api repos/o/r/merges -f base=main -f head=feature/x'
expect 2 'gh api -X PUT repos/o/r/contents/README.md -f message=x -f content=eA=='
expect 2 'gh api -X DELETE repos/o/r/branches/main/protection'
expect 2 'gh api -X POST repos/o/r/rulesets --input r.json'
expect 2 'gh api graphql -f query="mutation { updateRef(input:{}) { clientMutationId } }"'
expect 2 'gh api graphql -f query="mutation { mergePullRequest(input:{}) { clientMutationId } }"'
expect 2 'gh api graphql -f query="mutation { createCommitOnBranch(input:{}) { clientMutationId } }"'
expect 2 'cd x && gh api -X PATCH repos/o/r/git/refs/heads/main -f sha=abc'
# Blocked: switching off git-native hooks.
expect 2 'git -c core.hooksPath=/dev/null push origin main'
expect 2 'git -c "core.hooksPath=/dev/null" commit -m x'
expect 2 'git config core.hooksPath /tmp/empty'
expect 2 'git config --unset core.hooksPath'
expect 2 'git config --local core.hooksPath .githooks-off'

# Allowed: reads and unrelated calls.
expect 0 'gh api repos/o/r/git/refs/heads/main'
expect 0 'gh api repos/o/r/contents/README.md --jq .sha'
expect 0 'gh api -X GET repos/o/r/git/refs -f per_page=100'
expect 0 'gh api repos/o/r/branches/main/protection'
expect 0 'gh api repos/o/r/pulls/7 --jq .head.sha'
expect 0 'gh api graphql -f query="query { viewer { login } }"'
expect 0 'gh api -X POST repos/o/r/issues/3/comments -f body=hi'
expect 0 'git config --get core.hooksPath'
expect 0 'git config user.name ahmdgit'
expect 0 'git push origin feature/GH-4-x'

if [ "$fail" -ne 0 ]; then echo FAIL; exit 1; fi
echo PASS
