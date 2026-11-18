#!/bin/bash
# CLASS: CONTROL — local customisation (ADR-0054, #4).
#
# Blocks agent routes to a protected branch that do not go through
# `git push`, plus attempts to switch off the git-native hooks:
#
#   - `gh api` write calls (-X/--method POST|PUT|PATCH|DELETE, or a field flag
#     that implies POST) to:
#       git/refs, git/commits (ref moves and raw commits)
#       pulls/<n>/merge, merges (server-side merges)
#       contents/ (the Contents API commits straight to a branch)
#       branches/<b>/protection, rulesets (protection changes)
#   - `gh api graphql` carrying a ref, merge or commit mutation
#     (updateRef, updateRefs, createRef, deleteRef, mergePullRequest,
#     mergeBranch, createCommitOnBranch, enablePullRequestAutoMerge)
#   - `git config ... core.hooksPath` (set or unset) and
#     `git -c core.hooksPath=...`
#
# Read-only `gh api` calls and `git config --get core.hooksPath` are allowed.
# This is a guardrail against honest mistakes and casual bypasses, not a hard
# security boundary: the GitHub-side detective workflows and the owner's
# personal merge remain the final layers (ADR-0054).
#
# Fails closed: if the payload cannot be parsed but mentions `gh api` or
# `core.hooksPath`, it blocks.

set -u

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ -z "$COMMAND" ]; then
  if printf '%s' "$INPUT" | grep -qiE 'gh[[:space:]]+api|core\.hookspath'; then
    echo "BLOCKED: protected-ref gate cannot parse this command. Restore jq and retry." >&2
    exit 2
  fi
  exit 0
fi

block() {
  cat >&2 <<MSG
BLOCKED: $1
Changes reach a protected branch only through a pull request that the owner
merges (ADR-0054). Read-only gh api calls remain available.
MSG
  exit 2
}

LC=$(printf '%s' "$COMMAND" | tr '[:upper:]' '[:lower:]')

# --- git hooks path tampering -------------------------------------------------
if printf '%s' "$LC" | grep -qE 'git[^;&|]*[[:space:]]-c[[:space:]]*["'"'"']?core\.hookspath'; then
  block "overriding core.hooksPath for a git command is not available to agents."
fi
if printf '%s' "$LC" | grep -qE 'git[^;&|]*[[:space:]]config[^;&|]*core\.hookspath'; then
  if ! printf '%s' "$LC" | grep -qE 'git[^;&|]*[[:space:]]config[[:space:]]+(--get|--get-all|-l|--list)[^;&|]*core\.hookspath' ||
     printf '%s' "$LC" | grep -qE 'core\.hookspath[[:space:]]+[^;&|[:space:]]'; then
    block "changing core.hooksPath is not available to agents."
  fi
fi

# --- gh api -------------------------------------------------------------------
printf '%s' "$LC" | grep -qE '(^|[^a-z0-9_-])gh[[:space:]]+api([[:space:]]|$)' || exit 0

# GraphQL mutations that move refs, merge, or commit.
if printf '%s' "$LC" | grep -qE 'gh[[:space:]]+api[[:space:]].*graphql'; then
  if printf '%s' "$LC" | grep -qE 'updateref|updaterefs|createref|deleteref|mergepullrequest|mergebranch|createcommitonbranch|enablepullrequestautomerge'; then
    block "GraphQL ref, merge and commit mutations are not available to agents."
  fi
fi

SENSITIVE='(/git/refs|/git/commits|/pulls/[0-9]+/merge|/merges([^a-z]|$)|/contents/|/branches/[^[:space:]]+/protection|/rulesets)'
printf '%s' "$LC" | grep -qE "$SENSITIVE" || exit 0

WRITE=0
printf '%s' "$LC" | grep -qE '(-x|--method)[[:space:]=]*["'"'"']?(post|put|patch|delete)' && WRITE=1
# -f/-F (lower-cased here) and --field/--raw-field/--input imply POST.
printf '%s' "$LC" | grep -qE '[[:space:]](-f|--field|--raw-field|--input)([[:space:]=]|$)' && WRITE=1

# An explicit GET stays read-only even with query fields.
printf '%s' "$LC" | grep -qE '(-x|--method)[[:space:]=]*["'"'"']?get([^a-z]|$)' && WRITE=0

if [ "$WRITE" -eq 1 ]; then
  block "gh api write calls to refs, commits, merges, contents or branch protection are not available to agents."
fi
exit 0
